"""Suites: task loading, candidate grid, cost/time ESTIMATE (no model calls),
budgeted execution, aggregation, diagnostics and the plain-words recommendation.

Article rules implemented here:
  1  tasks mirror production: evals/tasks/*.json over evals/fixtures/* mini-repos.
  2  programmatic graders (graders.py); every task has a why_hard note; tasks were
     picked because a human judged them hard, not because a model failed them.
  3  each task runs on each candidate tier (haiku/sonnet) and, when the agent pins an
     effort, at that effort and at default effort.
  4  repeats (default 3): mean, run-to-run variance, 95% Wilson CI.
  5  seeded, stable 70/30 train / held-out split (common.split_ids).
  6  diagnostics: grader-twice, plumbing counted apart, headroom warning at >=95%.
  8  RECOMMENDATION in plain words; a difference inside the CI is called noise and
     produces "no change".
The interval treats each valid (task, repeat) trial as independent. Repeats of one
task are correlated, so the CI is somewhat too narrow; the text says "about".
"""
import glob
import json
import os
import re
import threading
import time
from concurrent.futures import ThreadPoolExecutor

import common
import runner

TIERS = ("haiku", "sonnet")
FLAKY_EPS = 1e-9


# ------------------------------------------------------------ loading
def load_routing_tasks(agents_filter=None):
    tasks = []
    for p in sorted(glob.glob(os.path.join(common.evals_dir(), "tasks", "*.json"))):
        d = common.read_json(p, {})
        for t in d.get("tasks", []):
            if agents_filter and t.get("agent") not in agents_filter:
                continue
            tasks.append(t)
    split = common.split_ids([(t["id"], t["agent"]) for t in tasks])
    for t in tasks:
        t["split"] = split[t["id"]]
    return tasks


def load_trigger_items(skills, skills_filter=None):
    d = common.read_json(os.path.join(common.evals_dir(), "triggers.json"), {}).get("skills", {})
    items = []
    for skill in sorted(d):
        if skill not in skills:
            continue
        if skills_filter and skill not in skills_filter:
            continue
        for cls, key in (("s", "should"), ("n", "should_not")):
            for i, prompt in enumerate(d[skill].get(key, [])):
                items.append({"id": "trig.%s.%s%d" % (skill, cls, i), "skill": skill, "should": cls == "s",
                              "prompt": prompt, "cls": key})
    split = common.split_ids([(it["id"], it["skill"] + ":" + it["cls"]) for it in items])
    for it in items:
        it["split"] = split[it["id"]]
    return items


def candidates(agent, grid=True):
    """Tiers x efforts. When the agent pins an effort, test that effort and default."""
    eff = agent.get("effort") or "default"
    efforts = [eff]
    if grid and eff != "default":
        efforts.append("default")
    return [{"tier": t, "effort": e} for e in efforts for t in TIERS]


def cand_key(c):
    return "%s@%s" % (c["tier"], c["effort"])


def current_cand(agent):
    return {"tier": common.tier_of(agent.get("model") or "sonnet"), "effort": agent.get("effort") or "default"}


def trigger_model():
    return os.environ.get("MOGGER_EVAL_TRIGGER_MODEL", "sonnet")


# ------------------------------------------------------------ estimate (rule: NO model calls)
def build_estimate(suite, repeats, jobs, agents, skills, agents_filter=None, skills_filter=None, grid=True):
    out = {"runs": 0, "usd": 0.0, "secs": 0.0, "models": set(), "by_suite": {}}
    if suite in ("routing", "all"):
        tasks = load_routing_tasks(agents_filter)
        n = 0
        usd = secs = 0.0
        for t in tasks:
            a = agents.get(t["agent"])
            if not a:
                continue
            for c in candidates(a, grid):
                c_usd, c_secs = common.est_trial("routing", c["tier"])
                n += repeats
                usd += repeats * c_usd
                secs += repeats * c_secs
                out["models"].add(c["tier"])
        out["by_suite"]["routing"] = {"runs": n, "usd": usd}
        out["runs"] += n
        out["usd"] += usd
        out["secs"] += secs
    if suite in ("triggers", "all"):
        items = load_trigger_items(skills, skills_filter)
        tier = common.tier_of(trigger_model())
        c_usd, c_secs = common.est_trial("triggers", tier)
        n = len(items) * repeats
        out["by_suite"]["triggers"] = {"runs": n, "usd": n * c_usd}
        out["runs"] += n
        out["usd"] += n * c_usd
        out["secs"] += n * c_secs
        if n:
            out["models"].add(tier)
    out["minutes"] = out["secs"] / max(jobs, 1) / 60.0
    return out


# ------------------------------------------------------------ budgeted execution
class Spend:
    def __init__(self, budget):
        self.budget = budget
        self.spent = 0.0
        self.inflight = 0.0
        self.stopped = False
        self.lock = threading.Lock()

    def try_start(self, est):
        with self.lock:
            if self.stopped or (self.budget is not None and self.spent + self.inflight >= self.budget - 1e-12):
                self.stopped = True
                return False
            self.inflight += est
            return True

    def left(self):
        with self.lock:
            return (self.budget - self.spent) if self.budget is not None else 1e9

    def finish(self, est, cost):
        with self.lock:
            self.inflight -= est
            self.spent += cost


def execute(plans, spend, jobs, log=print):
    """plans: list of {label, est_usd, fn(budget_left)->record}. Returns (records, skipped).
    A trial only starts while spend + in-flight estimate < budget, so the overshoot is
    bounded by the per-trial cap x jobs. Trials are ordered repeat-major so a partial
    run still covers every task."""
    records, lock = [], threading.Lock()
    counter = {"n": 0, "skipped": 0}
    total = len(plans)

    def work(plan):
        if not spend.try_start(plan["est_usd"]):
            with lock:
                counter["skipped"] += 1
            return
        try:
            rec = plan["fn"](spend.left())
        except Exception as e:  # never let one trial kill the run; count as plumbing
            rec = {"kind": plan.get("kind", ""), "task": plan["label"], "status": "api_error", "note": "runner crashed: %s" % e,
                   "passed": None, "cost_usd": 0.0, "cand": plan.get("cand", "")}
        spend.finish(plan["est_usd"], rec.get("cost_usd", 0.0))
        with lock:
            counter["n"] += 1
            records.append(rec)
            verdict = {True: "pass", False: "fail", None: rec.get("status", "?")}[rec.get("passed")]
            log("[%d/%d] %s %s $%.4f (spent $%.2f of $%.2f)" % (counter["n"], total, plan["label"], verdict,
                                                              rec.get("cost_usd", 0.0), spend.spent, spend.budget or 0))

    with ThreadPoolExecutor(max_workers=max(1, jobs)) as ex:
        list(ex.map(work, plans))
    return records, counter["skipped"]


def routing_plans(tasks, agents, repeats, run_dir, grid=True):
    plans = []
    for r in range(1, repeats + 1):
        for t in tasks:
            a = agents.get(t["agent"])
            if not a:
                continue
            for c in candidates(a, grid):
                est = common.est_trial("routing", c["tier"])[0]
                plans.append({"label": "%s %s #%d" % (t["id"], cand_key(c), r), "est_usd": est, "kind": "routing",
                              "cand": cand_key(c),
                              "fn": (lambda bl, t=t, a=a, c=c, r=r: runner.routing_trial(t, a, c, r, run_dir, bl))})
    return plans


def trigger_plans(items, plugin_dir, repeats, run_dir):
    model = trigger_model()
    est = common.est_trial("triggers", common.tier_of(model))[0]
    plans = []
    for r in range(1, repeats + 1):
        for it in items:
            plans.append({"label": "%s #%d" % (it["id"], r), "est_usd": est, "kind": "triggers", "cand": common.tier_of(model),
                          "fn": (lambda bl, it=it, r=r: runner.trigger_trial(it, plugin_dir, model, r, run_dir, bl))})
    return plans


# ------------------------------------------------------------ aggregation
def cell_stats(recs):
    valid = [r for r in recs if r.get("status") == "ok" and r.get("passed") is not None]
    plumb = {}
    for r in recs:
        if r.get("status") != "ok":
            plumb[r.get("status", "?")] = plumb.get(r.get("status", "?"), 0) + 1
    k = sum(1 for r in valid if r["passed"])
    n = len(valid)
    lo, hi = common.wilson(k, n)
    by_task = {}
    for r in valid:
        by_task.setdefault(r["task"], []).append(1.0 if r["passed"] else 0.0)
    vars_ = [common.sample_sd(v) ** 2 for v in by_task.values() if len(v) >= 2]
    flaky = sorted(t for t, v in by_task.items() if len(v) >= 2 and 0 < sum(v) < len(v))
    always_fail = sorted(t for t, v in by_task.items() if len(v) >= 2 and sum(v) == 0)
    return {"score": (float(k) / n if n else 0.0), "ci95": [lo, hi], "n": n, "k": k, "plumbing": plumb,
            "plumbing_n": sum(plumb.values()), "run_variance": common.mean(vars_) if vars_ else 0.0,
            "flaky_tasks": flaky, "always_fail": always_fail,
            "cost_usd": sum(r.get("cost_usd", 0.0) for r in recs)}


def _r(x, nd=4):
    return round(x, nd)


def recommend_agent(name, agent, cells, margin=0.10):
    """Rule 8. cells: {cand_key: stats}. Returns (verdict, plain-words text)."""
    cur = current_cand(agent)
    ck = cand_key(cur)
    if ck not in cells or cells[ck]["n"] == 0:
        return "inconclusive", "%s: no scored runs for its current setting (%s). No recommendation." % (name, ck)
    c = cells[ck]
    tot = c["n"] + c["plumbing_n"]
    if c["n"] < 6 or (tot and float(c["plumbing_n"]) / tot > 0.25):
        return "inconclusive", ("%s on %s: only %d scored runs and %d infrastructure problems. Too little to judge. "
                                "Run again with more repeats." % (name, cur["tier"].capitalize(), c["n"], c["plumbing_n"]))
    other = "sonnet" if cur["tier"] == "haiku" else "haiku"
    alts = [(k, v) for k, v in cells.items() if k.startswith(other + "@") and v["n"] > 0]
    if not alts:
        return "inconclusive", "%s: the %s runs did not produce scores. No recommendation." % (name, other.capitalize())
    alts.sort(key=lambda kv: -kv[1]["score"])
    ak, a = alts[0]
    d, lo, hi = common.diff_ci(c["k"], c["n"], a["k"], a["n"])
    cs = "%s on %s scored %d%% (CI %d-%d)" % (name, cur["tier"].capitalize(), common.pct(c["score"]), common.pct(c["ci95"][0]), common.pct(c["ci95"][1]))
    as_ = "%s %d%%" % (other.capitalize(), common.pct(a["score"]))
    if cur["tier"] == "haiku":
        if lo > 0:
            return "consider_sonnet", "%s vs %s: consider Sonnet. The gap of %d points is larger than noise." % (cs, as_, common.pct(d))
        if d >= margin:
            return "no_change_noise", ("%s vs %s: the gap is within noise, so no change is recommended. "
                                       "More repeats could settle it if it matters." % (cs, as_))
        return "keep_haiku", "%s vs %s: keep Haiku. Any gap is within noise." % (cs, as_)
    # current is sonnet: is Haiku good enough?
    d2, lo2, hi2 = common.diff_ci(c["k"], c["n"], a["k"], a["n"])
    if lo2 > -margin:
        return "consider_haiku", ("%s vs %s: consider Haiku. It is not worse by more than %d points, "
                                  "with confidence, and it costs less." % (cs, as_, common.pct(margin)))
    return "keep_sonnet", "%s vs %s: keep Sonnet. Haiku may be worse, or the data cannot rule that out." % (cs, as_)


def effort_note(name, agent, cells):
    cur = current_cand(agent)
    if cur["effort"] == "default":
        return ""
    a, b = cells.get(cand_key(cur)), cells.get("%s@default" % cur["tier"])
    if not a or not b or a["n"] == 0 or b["n"] == 0:
        return ""
    d, lo, hi = common.diff_ci(a["k"], a["n"], b["k"], b["n"])
    if lo > 0:
        return "%s: default effort scored %d%% vs %d%% at %s effort. Consider raising effort." % (name, common.pct(b["score"]), common.pct(a["score"]), cur["effort"])
    return "%s: %s effort is enough (default effort is not clearly better)." % (name, cur["effort"])


def aggregate_routing(records, agents, tasks):
    by_agent = {}
    for r in records:
        if r.get("kind") == "routing":
            by_agent.setdefault(r["agent"], []).append(r)
    split = {t["id"]: t["split"] for t in tasks}
    out = {"agents": {}, "plumbing": {}, "total_trials": 0}
    warnings, recs = [], []
    cur_k = cur_n = 0
    for name in sorted(by_agent):
        a = agents.get(name)
        if not a:
            continue
        cells = {}
        for ck in sorted(set(r["cand"] for r in by_agent[name])):
            sub = [r for r in by_agent[name] if r["cand"] == ck]
            st = cell_stats(sub)
            st["train"] = _split_score([r for r in sub if split.get(r["task"]) == "train"])
            st["heldout"] = _split_score([r for r in sub if split.get(r["task"]) == "heldout"])
            cells[ck] = st
        verdict, text = recommend_agent(name, a, cells)
        eff = effort_note(name, a, cells)
        cur = cells.get(cand_key(current_cand(a)))
        if cur:
            cur_k += cur["k"]
            cur_n += cur["n"]
        out["agents"][name] = {"current": cand_key(current_cand(a)), "candidates": _round_cells(cells),
                               "verdict": verdict, "recommendation": text, "effort_note": eff}
        recs.append(text)
        if eff:
            recs.append(eff)
        best = max((v["score"] for v in cells.values() if v["n"]), default=0.0)
        if best >= 0.95:
            warnings.append("Headroom: %s scores %d%% at its best. That is near the ceiling, so quality cannot be tuned further. Aim at cost, not quality." % (name, common.pct(best)))
        sonn = [v for k, v in cells.items() if k.startswith("sonnet") and v["n"]]
        hai = [v for k, v in cells.items() if k.startswith("haiku") and v["n"]]
        if sonn and hai:
            bs, bh = max(sonn, key=lambda v: v["score"]), max(hai, key=lambda v: v["score"])
            d, lo, hi = common.diff_ci(bs["k"], bs["n"], bh["k"], bh["n"])
            if hi < 0:
                warnings.append("%s: the stronger model scored LOWER than Haiku beyond noise. Tasks or the grader may be off. Read a transcript before trusting this." % name)
        for ck, v in cells.items():
            if v["always_fail"]:
                warnings.append("%s %s: task(s) %s failed every repeat. That usually means an ambiguous task or a wrong grader. Read the transcript." % (name, ck, ", ".join(v["always_fail"])))
            if v["run_variance"] > 0.15:
                warnings.append("%s %s: high run-to-run variance (%.2f). Scores may swing between runs." % (name, ck, v["run_variance"]))
    for r in records:
        if r.get("kind") == "routing":
            out["total_trials"] += 1
            if r.get("status") != "ok":
                out["plumbing"][r["status"]] = out["plumbing"].get(r["status"], 0) + 1
    lo, hi = common.wilson(cur_k, cur_n)
    out.update(score=(float(cur_k) / cur_n if cur_n else 0.0), ci95=[lo, hi], n=cur_n)
    return out, warnings, recs


def _split_score(sub):
    v = [r for r in sub if r.get("status") == "ok" and r.get("passed") is not None]
    k = sum(1 for r in v if r["passed"])
    return {"score": (float(k) / len(v) if v else 0.0), "n": len(v)}


def _round_cells(cells):
    out = {}
    for k, v in cells.items():
        w = dict(v)
        w["score"] = _r(v["score"])
        w["ci95"] = [_r(x) for x in v["ci95"]]
        w["run_variance"] = _r(v["run_variance"])
        w["cost_usd"] = _r(v["cost_usd"], 5)
        out[k] = w
    return out


def aggregate_triggers(records, items):
    split = {it["id"]: it["split"] for it in items}
    by_skill = {}
    for r in records:
        if r.get("kind") == "triggers":
            by_skill.setdefault(r["skill"], []).append(r)
    out = {"skills": {}, "plumbing": {}, "total_trials": 0}
    warnings, recs = [], []
    K = N = 0
    for skill in sorted(by_skill):
        rs = by_skill[skill]
        st = cell_stats(rs)
        sh = [r for r in rs if r.get("status") == "ok" and r["should"]]
        sn = [r for r in rs if r.get("status") == "ok" and not r["should"]]
        recall = float(sum(1 for r in sh if r["triggered"])) / len(sh) if sh else None
        false_rate = float(sum(1 for r in sn if r["triggered"])) / len(sn) if sn else None
        st.update(recall=recall, false_rate=false_rate,
                  train=_split_score([r for r in rs if split.get(r["task"]) == "train"]),
                  heldout=_split_score([r for r in rs if split.get(r["task"]) == "heldout"]))
        out["skills"][skill] = _round_cells({skill: st})[skill]
        K += st["k"]
        N += st["n"]
    weak = sorted(out["skills"].items(), key=lambda kv: kv[1]["score"])[:3]
    for name, v in weak:
        if v["n"] and v["score"] < 0.8:
            rc = "n/a" if v["recall"] is None else "%d%%" % common.pct(v["recall"])
            fr = "n/a" if v["false_rate"] is None else "%d%%" % common.pct(v["false_rate"])
            recs.append("Skill %s: right on %d%% of prompts (fires when it should: %s; fires when it should not: %s). "
                        "Try: mogger-eval.sh hillclimb --skill %s" % (name, common.pct(v["score"]), rc, fr, name))
    for r in records:
        if r.get("kind") == "triggers":
            out["total_trials"] += 1
            if r.get("status") != "ok":
                out["plumbing"][r["status"]] = out["plumbing"].get(r["status"], 0) + 1
    lo, hi = common.wilson(K, N)
    out.update(score=(float(K) / N if N else 0.0), ci95=[lo, hi], n=N)
    if N and out["score"] >= 0.95:
        warnings.append("Headroom: skill triggering scores %d%%. Near the ceiling. Aim at cost, not quality." % common.pct(out["score"]))
    return out, warnings, recs


def diagnostics(records, repeats, partial):
    w = []
    flaky = sorted(set(r["task"] for r in records if r.get("grader_flaky")))
    for t in flaky:
        w.append("Grader gave different verdicts on identical output for task %s. Fix the grader before trusting any score." % t)
    plumb = {}
    for r in records:
        if r.get("status") != "ok":
            plumb[r.get("status", "?")] = plumb.get(r.get("status", "?"), 0) + 1
    if plumb:
        tot = sum(plumb.values())
        w.append("%d of %d runs had infrastructure problems (%s). They are not scored and not counted as wrong answers." %
                 (tot, len(records), ", ".join("%s %d" % (k, v) for k, v in sorted(plumb.items()))))
        if len(records) and float(tot) / len(records) > 0.10:
            w.append("More than 10%% of runs hit plumbing problems. Fix that (network, timeouts, auth) before reading the scores.")
    if repeats < 3:
        w.append("Only %d repeat(s). Run-to-run noise cannot be measured well. Use 3 or more." % repeats)
    est_src = sum(1 for r in records if r.get("cost_source") == "estimate")
    if est_src:
        w.append("%d runs had no cost figure from the CLI; their cost is estimated from token counts." % est_src)
    if partial:
        w.append("PARTIAL: the run stopped because the budget was reached. Some runs were not done. Scores use fewer repeats.")
    return w
