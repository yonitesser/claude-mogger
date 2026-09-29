"""Hillclimber for ONE skill description against the triggers suite.

Why skill triggering (article, "Hillclimbing"): it is cheap to iterate (one line of
text), attributable (the trigger rate is directly coupled to the description) and
well scoped.

Rules implemented (article: "Overfitting" and "/claude-api hillclimb"):
  5  train / held-out split (seeded, stable, 70/30, stratified by should/should-not).
     The proposer sees TRAIN results only. Held-out prompts are never put in any prompt;
     assert_no_leak() enforces it in code.
     A patch is kept only if train AND held-out do not regress and train improves beyond
     noise. Train up + held-out flat (with room to move) => reverted as overfitting.
     Never paste failure content: a patch may not contain any substring of >= 20 chars
     that is taken from a task input (check_patch).
  6  Before round 1: noise check (noise must be below the smallest gain we would act
     on, else say so and suggest more repeats) and headroom check (>=95% => aim at
     cost, not quality). After 2 stalled rounds: reflection, which buckets the
     remaining train failures by cause and makes NO edit.
One patch per round. The hillclimber never edits plugin files; it writes a proposal
under <state>/evals/proposals/. `apply` is a separate, explicit command.
"""
import difflib
import json
import os
import re
import shutil
import tempfile
import time

import common
import runner
import suites

LEAK_LEN = 20


def normalize(s):
    return " ".join(s.lower().split())


def windows(s, n=LEAK_LEN):
    s = normalize(s)
    return set(s[i:i + n] for i in range(0, max(0, len(s) - n + 1)))


def find_leak(text, inputs, base="", exempt=()):
    """First >=20-char normalized substring of any input that appears in text but not in
    base. `exempt` inputs (the TRAIN prompts the proposer may legitimately see) are
    subtracted first, so wording shared with a train prompt is not held against the text."""
    added = windows(text) - windows(base)
    if not added:
        return None
    ex = set()
    for e in exempt:
        ex |= windows(e)
    for inp in inputs:
        hit = (windows(inp) - ex) & added
        if hit:
            return sorted(hit)[0]
    return None


def assert_no_leak(text, inputs, base="", exempt=()):
    hit = find_leak(text, inputs, base, exempt)
    if hit is not None:
        raise AssertionError("text contains task input (>=%d chars): %r" % (LEAK_LEN, hit))


def check_patch(new_desc, cur_desc, inputs):
    if not new_desc or not new_desc.strip():
        return False, "empty description"
    if "\n" in new_desc.strip():
        return False, "description must be one line"
    if len(new_desc) > 1000:
        return False, "description too long (%d chars)" % len(new_desc)
    if normalize(new_desc) == normalize(cur_desc):
        return False, "no change"
    hit = find_leak(new_desc, inputs, cur_desc)
    if hit is not None:
        return False, "patch copies task text (%r...)" % hit[:20]
    return True, ""


def proposer_prompt(skill, cur_desc, body_head, train_rows):
    lines = ["MOGGER-PROPOSER",
             "You improve the description of one Claude Code skill so the skill is invoked when it should be, and only then.",
             "Skill name: %s" % skill,
             "Current description: %s" % cur_desc,
             "What the skill does (start of its instructions):",
             body_head,
             "",
             "Results on TRAINING prompts with the current description. 'invoked' is how many repeats called this skill;",
             "'other' lists other skills that were called instead.",
             ]
    for row in train_rows:
        lines.append("- expected: %s | invoked %d/%d | other: %s | prompt: %s" % (
            "invoke" if row["should"] else "do NOT invoke", row["invoked"], row["n"], ", ".join(row["other"]) or "none", row["prompt"]))
    lines += ["",
              "Rules:",
              "- Propose exactly ONE change. Reply with a single JSON object {\"description\": \"...\"} and nothing else.",
              "- Fix the cause at its root: say what the skill is for and which situations call for it, and what does not.",
              "- Never quote or paraphrase the prompts above. Describe kinds of situations in your own words.",
              "- One line, under 900 characters."]
    return "\n".join(lines)


def parse_proposal(text):
    m = re.search(r"\{.*\}", text or "", re.S)
    if not m:
        return None
    try:
        d = json.loads(m.group(0))
    except Exception:
        return None
    desc = d.get("description") if isinstance(d, dict) else None
    return " ".join(desc.split()) if isinstance(desc, str) else None


def call_proposer(prompt, round_no, spend):
    model = os.environ.get("MOGGER_EVAL_PROPOSER_MODEL", "sonnet")
    cwd = tempfile.mkdtemp(prefix="mogger-eval-prop-")
    try:
        cap = min(0.30, max(spend.left(), 0.01))
        cmd = [common.claude_bin(), "-p", prompt, "--output-format", "stream-json", "--verbose", "--model", model,
               "--max-turns", "1", "--permission-mode", "dontAsk", "--no-session-persistence",
               "--max-budget-usd", "%.2f" % cap] + runner._extra_args()
        lines, rc, timed_out, _, err = runner.run_claude(cmd, cwd, runner._child_env("proposer-%d" % round_no, round_no), 180)
        info = runner.parse_stream(lines)
        cost, _ = runner.cost_of(info, common.tier_of(model))
        spend.finish(0.0, cost)
        status, note = runner.classify(info, timed_out, rc, err)
        return (parse_proposal(info["text"]) if status == "ok" else None), cost, status
    finally:
        shutil.rmtree(cwd, ignore_errors=True)


# ------------------------------------------------------------ scoring helpers
def split_scores(records, split_of):
    """-> {split: {'acc', 'n', 'k', 'per_repeat': [acc per repeat], 'sd'}} over valid trials."""
    out = {}
    for sp in ("train", "heldout"):
        rs = [r for r in records if split_of.get(r["task"]) == sp and r.get("status") == "ok" and r.get("passed") is not None]
        k = sum(1 for r in rs if r["passed"])
        reps = {}
        for r in rs:
            reps.setdefault(r["repeat"], []).append(1.0 if r["passed"] else 0.0)
        per = [common.mean(v) for _, v in sorted(reps.items())]
        out[sp] = {"acc": (float(k) / len(rs) if rs else 0.0), "n": len(rs), "k": k, "per_repeat": per,
                   "sd": common.sample_sd(per)}
    return out


def decide(cur, new, min_gain):
    """cur/new: split_scores. Returns (kept: bool, reason)."""
    nt = 2 * cur["train"]["sd"]
    nh = 2 * cur["heldout"]["sd"]
    tg = new["train"]["acc"] - cur["train"]["acc"]
    hg = new["heldout"]["acc"] - cur["heldout"]["acc"]
    if tg < -nt - 1e-9 or hg < -nh - 1e-9:
        return False, "regression (train %+.0f pts, held-out %+.0f pts)" % (100 * tg, 100 * hg)
    thr = max(min_gain, nt)
    if tg <= thr + 1e-9:
        return False, "train gain %+.0f pts is not beyond noise/min-gain (%.0f pts)" % (100 * tg, 100 * thr)
    if hg < -1e-9:
        return False, "held-out dropped %.0f pts" % (-100 * hg)
    if hg <= nh + 1e-9 and cur["heldout"]["acc"] < 1.0 - 1e-9:
        return False, "overfitting: train %+.0f pts but held-out flat (%+.0f pts)" % (100 * tg, 100 * hg)
    return True, "train %+.0f pts, held-out %+.0f pts" % (100 * tg, 100 * hg)


def reflect(records, items_by_id):
    """Stall reflection (no edit): bucket remaining TRAIN failures by cause."""
    buckets = {}
    per = {}
    for r in records:
        it = items_by_id.get(r["task"])
        if not it or it["split"] != "train":
            continue
        per.setdefault(r["task"], []).append(r)
    for tid, rs in per.items():
        it = items_by_id[tid]
        plumb = [r for r in rs if r.get("status") != "ok"]
        valid = [r for r in rs if r.get("status") == "ok"]
        wrong = [r for r in valid if not r["passed"]]
        if plumb and not valid:
            buckets.setdefault("infrastructure problem only (timeouts or API errors), not a description issue", []).append(tid)
        elif wrong and len(wrong) < len(valid):
            buckets.setdefault("flaky: passes on some repeats (run-to-run noise; more repeats, not an edit)", []).append(tid)
        elif wrong and it["should"]:
            others = sorted(set(s for r in wrong for s in r.get("invoked", [])))
            key = "should fire but another skill won (%s)" % ", ".join(others) if others else "should fire but no skill was called (prompt may be too generic or ambiguous)"
            buckets.setdefault(key, []).append(tid)
        elif wrong:
            buckets.setdefault("fires on a near-miss it should ignore (description too broad)", []).append(tid)
    return buckets


# ------------------------------------------------------------ main loop
def hillclimb(skill, skills, agents_unused, rounds, repeats, spend, jobs, run_dir, min_gain=0.10, force=False,
              log=print):
    if skill not in skills:
        common.die("Unknown skill %r. Known: %s" % (skill, ", ".join(sorted(skills))))
    items = suites.load_trigger_items(skills, [skill])
    if not items:
        common.die("No trigger prompts for %s in evals/triggers.json." % skill)
    items_by_id = dict((it["id"], it) for it in items)
    split_of = dict((it["id"], it["split"]) for it in items)
    all_inputs = [it["prompt"] for it in items]
    heldout_inputs = [it["prompt"] for it in items if it["split"] == "heldout"]
    train_items = [it for it in items if it["split"] == "train"]
    root = common.plugin_root()
    base_desc = skills[skill]["description"]
    body_head = "\n".join(common.split_frontmatter(skills[skill]["text"])[2].strip().split("\n")[:30])
    out = {"skill": skill, "ts": common.now_iso(), "fingerprint": common.fingerprint(), "base_description": base_desc,
           "rounds": [], "partial": False, "warnings": [], "min_gain": min_gain, "repeats": repeats,
           "train_n_prompts": len(train_items), "heldout_n_prompts": len(items) - len(train_items)}

    def evaluate(desc):
        pd = runner.make_plugin_copy(root, {skill: desc})
        try:
            recs, skipped = suites.execute(suites.trigger_plans(items, pd, repeats, run_dir), spend, jobs, log)
        finally:
            shutil.rmtree(pd, ignore_errors=True)
        return recs, skipped

    log("Baseline: %d train and %d held-out prompts x %d repeats." % (len(train_items), out["heldout_n_prompts"], repeats))
    recs, skipped = evaluate(base_desc)
    if skipped:
        out.update(partial=True)
        out["warnings"].append("Budget reached during the baseline. Nothing was proposed.")
        out["baseline_incomplete"] = True
        return finish(out, base_desc, base_desc, None, None, spend, [], {})
    cur = split_scores(recs, split_of)
    base = cur
    cur_recs = recs
    out["baseline"] = _brief(cur)
    tot_acc = (cur["train"]["k"] + cur["heldout"]["k"]) / float(max(1, cur["train"]["n"] + cur["heldout"]["n"]))
    noise = 2 * cur["train"]["sd"]
    plumb = [r for r in recs if r.get("status") != "ok"]
    if plumb:
        out["warnings"].append("%d baseline runs had plumbing problems and were not scored." % len(plumb))
    if repeats < 2:
        out["warnings"].append("With 1 repeat the noise cannot be measured. Use --repeats 3 or more.")
    if not force and tot_acc >= 0.95:
        out["warnings"].append("Headroom: baseline is %d%%. Near the ceiling, so a quality hillclimb has little to gain. Aim at cost, not quality. Stopped (use --force to try anyway)." % common.pct(tot_acc))
        out["stopped"] = "headroom"
        return finish(out, base_desc, base_desc, base, cur, spend, [], {})
    if not force and repeats >= 2 and noise > min_gain + 1e-9:
        need = int(repeats * (noise / min_gain) ** 2) + 1
        out["warnings"].append("Noise (about %d pts between repeats) is larger than the smallest gain we would act on (%d pts). "
                               "Use more repeats (try --repeats %d) or more prompts. Stopped (use --force to try anyway)." % (
                                   common.pct(noise), common.pct(min_gain), need))
        out["stopped"] = "noise"
        return finish(out, base_desc, base_desc, base, cur, spend, [], {})

    cur_desc = base_desc
    stalled = 0
    reflection = {}
    for rd in range(1, rounds + 1):
        if stalled >= 2:
            reflection = reflect(cur_recs, items_by_id)
            out["rounds"].append({"round": rd, "action": "reflect", "decision": "no edit", "buckets": reflection})
            log("Two rounds in a row did not help. Reflecting on the remaining train failures (no edit).")
            break
        rows = []
        for it in train_items:
            rs = [r for r in cur_recs if r["task"] == it["id"] and r.get("status") == "ok"]
            rows.append({"should": it["should"], "invoked": sum(1 for r in rs if r.get("triggered")), "n": len(rs),
                         "other": sorted(set(s for r in rs for s in r.get("invoked", []) if s != skill)), "prompt": it["prompt"]})
        prompt = proposer_prompt(skill, cur_desc, body_head, rows)
        assert_no_leak(prompt, heldout_inputs, exempt=[it["prompt"] for it in train_items])  # held-out is never shown to the proposer
        desc, pcost, pstatus = call_proposer(prompt, rd, spend)
        entry = {"round": rd, "proposer_status": pstatus, "proposer_cost_usd": round(pcost, 5)}
        if desc is None:
            entry.update(action="proposer_failed", decision="reverted", reason="no usable proposal (%s)" % pstatus)
            out["rounds"].append(entry)
            stalled += 1
            continue
        ok, why = check_patch(desc, cur_desc, all_inputs)
        entry["description"] = desc
        if not ok:
            entry.update(action="guard", decision="rejected", reason=why)
            out["rounds"].append(entry)
            log("Round %d rejected before testing: %s" % (rd, why))
            stalled += 1
            continue
        recs2, skipped2 = evaluate(desc)
        if skipped2:
            entry.update(action="budget", decision="discarded", reason="budget reached mid-round")
            out["rounds"].append(entry)
            out["partial"] = True
            break
        new = split_scores(recs2, split_of)
        kept, reason = decide(cur, new, min_gain)
        entry.update(action="patch", decision="kept" if kept else "reverted", reason=reason,
                     train={"before": round(cur["train"]["acc"], 4), "after": round(new["train"]["acc"], 4)},
                     heldout={"before": round(cur["heldout"]["acc"], 4), "after": round(new["heldout"]["acc"], 4)})
        out["rounds"].append(entry)
        log("Round %d: %s (%s)." % (rd, "kept" if kept else "reverted", reason))
        if kept:
            cur_desc, cur, cur_recs, stalled = desc, new, recs2, 0
        else:
            stalled += 1
    return finish(out, base_desc, cur_desc, base, cur, spend, [], reflection)


def _brief(sc):
    return {sp: {"acc": round(v["acc"], 4), "n": v["n"], "k": v["k"], "noise_pts": round(200 * v["sd"], 1)} for sp, v in sc.items()}


def finish(out, base_desc, final_desc, base, cur, spend, _unused, reflection):
    out["final_description"] = final_desc
    out["changed"] = normalize(final_desc) != normalize(base_desc)
    out["cost_usd"] = round(spend.spent, 5)
    out["reflection"] = reflection
    if base is not None and cur is not None:
        out["final"] = _brief(cur)
        d, lo, hi = common.diff_ci(base["heldout"]["k"], base["heldout"]["n"], cur["heldout"]["k"], cur["heldout"]["n"])
        out["heldout_gain"] = {"points": round(100 * d, 1), "ci95_points": [round(100 * lo, 1), round(100 * hi, 1)]}
        td, tlo, thi = common.diff_ci(base["train"]["k"], base["train"]["n"], cur["train"]["k"], cur["train"]["n"])
        out["train_gain"] = {"points": round(100 * td, 1), "ci95_points": [round(100 * tlo, 1), round(100 * thi, 1)]}
        if not out["changed"]:
            out["recommend_apply"] = False
            out["verdict"] = "No patch survived the checks. Keep the description as it is."
        elif lo > 0:
            out["recommend_apply"] = True
            out["verdict"] = "Held-out prompts improved by %d points (CI %d to %d). Worth applying." % (round(100 * d), round(100 * lo), round(100 * hi))
        else:
            out["recommend_apply"] = False
            out["verdict"] = ("Held-out gain is %d points (CI %d to %d): within noise. No change recommended. "
                              "More repeats would give a firmer answer." % (round(100 * d), round(100 * lo), round(100 * hi)))
    else:
        out["recommend_apply"] = False
        out["verdict"] = out["warnings"][-1] if out["warnings"] else "No result."
    return out


def write_proposal(out, skills, state):
    pid = "%s-%s" % (out["skill"], time.strftime("%Y%m%d%H%M%S", time.gmtime()))
    d = os.path.join(state, "proposals")
    os.makedirs(d, exist_ok=True)
    out["id"] = pid
    common.write_json(os.path.join(d, pid + ".json"), out)
    diff = "".join(difflib.unified_diff(["description: " + out["base_description"] + "\n"],
                                        ["description: " + out["final_description"] + "\n"],
                                        "plugin/skills/%s/SKILL.md" % out["skill"], "proposed/skills/%s/SKILL.md" % out["skill"]))
    open(os.path.join(d, pid + ".diff"), "w").write(diff)
    return pid
