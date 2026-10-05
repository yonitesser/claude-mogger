"""mogger-eval command line (called by scripts/mogger-eval.sh). Python 3 stdlib only.
See scripts/mogger-eval.sh for the contract and the article rules."""
import argparse
import calendar
import difflib
import os
import shutil
import sys
import time

import common
import ab
import graders
import hillclimb as hc
import report
import runner
import suites


def out(msg=""):
    sys.stdout.write(msg + "\n")
    sys.stdout.flush()


def sdir():
    d = common.state_dir()
    os.makedirs(d, exist_ok=True)
    return d


def project_dir():
    return os.path.abspath(os.environ.get("MOGGER_PROJECT_DIR") or os.getcwd())


def consent_path():
    return os.path.join(common.state_dir(), "consent.json")


def read_consent():
    d = common.read_json(consent_path(), None)
    if isinstance(d, dict) and isinstance(d.get("budget_usd"), (int, float)) and d["budget_usd"] > 0:
        return d
    return None


def parse_budget(s):
    try:
        v = float(s)
    except (TypeError, ValueError):
        common.die("--budget needs a number of US dollars, for example --budget 5")
    if not (v > 0) or v != v or v == float("inf"):
        common.die("--budget must be more than 0")
    return v


def suite_arg(s):
    if s not in ("routing", "triggers", "all"):
        common.die("--suite must be routing, triggers or all")
    return s


def csv_arg(s):
    return [x.strip() for x in s.split(",") if x.strip()] if s else None


# ------------------------------------------------------------ estimate
def cmd_estimate(a):
    agents, skills = common.load_agents(), common.load_skills()
    est = suites.build_estimate(suite_arg(a.suite), a.repeats, a.jobs, agents, skills, csv_arg(a.agents), csv_arg(a.skills),
                                not a.no_effort_grid)
    out("ESTIMATE only. No model calls were made.")
    out("suite: %s" % a.suite)
    out("runs: %d" % est["runs"])
    for k, v in sorted(est["by_suite"].items()):
        out("  %s: %d runs, about $%.2f" % (k, v["runs"], v["usd"]))
    out("models: %s" % (",".join(sorted(est["models"])) or "none"))
    out("estimated_usd: %.2f (ESTIMATE: token counts x templates/pricing.json, not a bill)" % est["usd"])
    out("minutes: %d (ESTIMATE, %d parallel runs)" % (int(round(est["minutes"])), a.jobs))
    out("repeats: %d" % a.repeats)
    out("This would run %d headless Claude sessions for about $%.2f and %d minutes." % (est["runs"], est["usd"], int(round(est["minutes"]))))
    return 0


# ------------------------------------------------------------ consent
def cmd_consent(a):
    if a.revoke:
        try:
            os.remove(consent_path())
            out("Consent removed. Evals will not run until you grant a budget again.")
        except OSError:
            out("There was no consent to remove.")
        return 0
    if a.budget is None:
        common.die("Usage: mogger-eval.sh consent --budget USD  (or --revoke)")
    b = parse_budget(a.budget)
    common.write_json(consent_path(), {"budget_usd": b, "ts": common.now_iso(),
                                       "note": a.note or "User allowed paid eval runs up to this budget."})
    out("Consent saved: evals may spend up to about $%.2f per run (estimate). Revoke with: mogger-eval.sh consent --revoke" % b)
    return 0


# ------------------------------------------------------------ run
def resolve_budget(a):
    if a.budget is not None:
        return parse_budget(a.budget)
    c = read_consent()
    if c:
        return float(c["budget_usd"])
    common.die("Refusing to run: there is no consent and no --budget.\n"
               "Evals call the model and cost money. Run  mogger-eval.sh estimate  first.\n"
               "Then either  mogger-eval.sh consent --budget USD  or pass --budget USD to run.")


def model_list(recs):
    return sorted(set(r["tier"] for r in recs if r.get("tier")))


def cmd_run(a):
    budget = resolve_budget(a)
    agents, skills = common.load_agents(), common.load_skills()
    suite = suite_arg(a.suite)
    af, sf, grid = csv_arg(a.agents), csv_arg(a.skills), not a.no_effort_grid
    est = suites.build_estimate(suite, a.repeats, a.jobs, agents, skills, af, sf, grid)
    out("Plan: %d runs, estimated $%.2f (ESTIMATE), budget $%.2f." % (est["runs"], est["usd"], budget))
    if est["usd"] > budget:
        out("The estimate is above the budget. The run will stop at the budget and give partial results.")
    if est["runs"] == 0:
        common.die("Nothing to run (no tasks or prompts match).")
    run_id = time.strftime("%Y%m%d%H%M%S", time.gmtime())
    state = sdir()
    run_dir = os.path.join(state, "runs", run_id)
    os.makedirs(run_dir, exist_ok=True)
    result = {"ts": common.now_iso(), "fingerprint": common.fingerprint(), "run_id": run_id, "suites": {},
              "warnings": [], "recommendations": [], "partial": False, "budget_usd": budget,
              "transcripts_dir": os.path.join("runs", run_id), "estimate_notice": "Costs are estimates, not a bill."}
    remaining = budget
    parts = [s for s in ("routing", "triggers") if suite in (s, "all") and est["by_suite"].get(s, {}).get("runs")]
    all_records = []
    for s in parts:
        share = est["by_suite"][s]["usd"] / max(sum(est["by_suite"][p]["usd"] for p in parts if p >= s), 1e-9)
        spend = suites.Spend(remaining if s == parts[-1] else remaining * share)
        if s == "routing":
            tasks = suites.load_routing_tasks(af)
            plans = suites.routing_plans(tasks, agents, a.repeats, run_dir, grid)
            recs, skipped = suites.execute(plans, spend, a.jobs, out)
            agg, warns, recos = suites.aggregate_routing(recs, agents, tasks)
        else:
            items = suites.load_trigger_items(skills, sf)
            pd = runner.make_plugin_copy(common.plugin_root())
            try:
                plans = suites.trigger_plans(items, pd, a.repeats, run_dir)
                recs, skipped = suites.execute(plans, spend, a.jobs, out)
            finally:
                shutil.rmtree(pd, ignore_errors=True)
            agg, warns, recos = suites.aggregate_triggers(recs, items)
        remaining = max(remaining - spend.spent, 0.0)
        agg["cost_usd"] = round(sum(r.get("cost_usd", 0.0) for r in recs), 5)
        agg["models"] = model_list(recs)
        agg["skipped_runs"] = skipped
        agg["planned_runs"] = len(plans)
        if skipped:
            result["partial"] = True
        result["suites"][s] = agg
        result["warnings"] += warns
        result["recommendations"] += recos
        all_records += recs
    result["warnings"] += suites.diagnostics(all_records, a.repeats, result["partial"])
    result["spent_usd"] = round(sum(r.get("cost_usd", 0.0) for r in all_records), 5)
    common.write_json(os.path.join(state, "last.json"), result)
    report.write_reports(result, state)
    out("")
    out(report.plain_text(result).rstrip())
    out("")
    out("Saved: %s" % os.path.join(state, "last.json"))
    out("Report page: %s" % os.path.join(state, "report.html"))
    return 0


# ------------------------------------------------------------ status / report
def age_words(ts):
    try:
        t = calendar.timegm(time.strptime(ts, "%Y-%m-%dT%H:%M:%SZ"))
    except Exception:
        return "unknown age"
    s = max(0, int(time.time() - t))
    if s < 90:
        return "%d seconds ago" % s
    if s < 5400:
        return "%d minutes ago" % (s // 60)
    if s < 172800:
        return "%d hours ago" % (s // 3600)
    return "%d days ago" % (s // 86400)


def cmd_status(a):
    state = common.state_dir()
    last = common.read_json(os.path.join(state, "last.json"), None)
    fp = common.fingerprint()
    if last:
        out("last run: %s (%s)%s" % (age_words(last.get("ts", "")), last.get("ts", "?"), ", PARTIAL" if last.get("partial") else ""))
        out("fingerprint: %s" % ("unchanged since the last run" if last.get("fingerprint") == fp
                                 else "CHANGED since the last run (agents or skill descriptions were edited)"))
    else:
        out("last run: none yet")
        out("fingerprint: %s (no earlier run to compare)" % fp)
    c = read_consent()
    out("consent: %s" % ("budget $%.2f granted %s" % (c["budget_usd"], c.get("ts", "?")) if c else "none (evals will not run without --budget)"))
    pidf = os.path.join(state, "running.pid")
    running = "no"
    if os.path.isfile(pidf):
        try:
            pid = int(open(pidf).read().strip())
            os.kill(pid, 0)
            running = "yes (pid %d)" % pid
        except (ValueError, OSError):
            running = "no (stale pid file)"
    out("running: %s" % running)
    return 0


def cmd_report(a):
    last = common.read_json(os.path.join(common.state_dir(), "last.json"), None)
    if not last:
        out("No eval results yet. Run  mogger-eval.sh estimate  and then  mogger-eval.sh run.")
        return 0
    sys.stdout.write(report.plain_text(last))
    return 0


# ------------------------------------------------------------ hillclimb / apply
def cmd_hillclimb(a):
    budget = resolve_budget(a)
    skills = common.load_skills()
    state = sdir()
    run_dir = os.path.join(state, "runs", "hc-" + time.strftime("%Y%m%d%H%M%S", time.gmtime()))
    os.makedirs(run_dir, exist_ok=True)
    spend = suites.Spend(budget)
    res = hc.hillclimb(a.skill, skills, None, a.rounds, a.repeats, spend, a.jobs, run_dir, a.min_gain, a.force, out)
    pid = hc.write_proposal(res, skills, state)
    out("")
    for w in res["warnings"]:
        out("Warning: " + w)
    for r in res["rounds"]:
        if r.get("action") == "reflect":
            out("Round %d: stall reflection, no edit. Remaining train failures by cause:" % r["round"])
            for k, v in sorted(r["buckets"].items()):
                out("  - %s: %d prompt(s)" % (k, len(v)))
        else:
            out("Round %d: %s. %s" % (r["round"], r.get("decision", "?"), r.get("reason", "")))
    out(res["verdict"])
    if res.get("partial"):
        out("PARTIAL: the budget was reached. Results are incomplete.")
    out("Proposal: %s" % os.path.join(state, "proposals", pid + ".json"))
    out("Nothing in the plugin was edited. To write it as a project override: mogger-eval.sh apply %s --yes" % pid)
    return 0


def safe_target(target):
    """A write target must sit under <project>/.claude/ and never inside the plugin dir."""
    rt = os.path.realpath(target)
    claude = os.path.realpath(os.path.join(project_dir(), ".claude")) + os.sep
    plug = os.path.realpath(common.plugin_root()) + os.sep
    if not rt.startswith(claude):
        return False, "target is not under the project's .claude/ folder"
    if rt.startswith(plug) and not plug.startswith(claude) and not claude.startswith(plug):
        return False, "target is inside the plugin folder"
    if rt.startswith(plug) and plug.startswith(claude):
        return False, "target is inside the plugin folder"
    return True, ""


def cmd_apply(a):
    pid = a.proposal[:-5] if a.proposal.endswith(".json") else a.proposal
    prop = common.read_json(os.path.join(common.state_dir(), "proposals", pid + ".json"), None)
    if not prop:
        common.die("No proposal named %s in %s" % (pid, os.path.join(common.state_dir(), "proposals")))
    skill = prop["skill"]
    target = a.target or os.path.join(project_dir(), ".claude", "skills", skill, "SKILL.md")
    if os.path.isfile(target):
        cur = open(target).read()
    else:
        skills = common.load_skills()
        cur = skills[skill]["text"] if skill in skills else None
        if cur is None:
            common.die("Skill %s is not in this plugin." % skill)
    new = runner.replace_description(cur, prop["final_description"])
    diff = "".join(difflib.unified_diff(cur.splitlines(True), new.splitlines(True), target + " (now)", target + " (proposed)"))
    out(diff.rstrip() if diff else "The proposal makes no change to this file.")
    if not a.yes:
        out("Nothing written. Add --yes to write this project-level override.")
        return 0
    ok, why = safe_target(target)
    if not ok:
        out("Refusing to write: %s. Only files under .claude/ in your project are allowed." % why)
        return 2
    if not prop.get("recommend_apply") and not a.force:
        out("Refusing to write: the eval says this change is not clearly better (%s). Use --force to write anyway." % prop.get("verdict", ""))
        return 2
    os.makedirs(os.path.dirname(target), exist_ok=True)
    tmp = target + ".tmp%d" % os.getpid()
    with open(tmp, "w") as f:
        f.write(new)
    os.replace(tmp, target)
    out("Written: %s" % target)
    out("The plugin's own file was not touched.")
    return 0


# ------------------------------------------------------------ validate
def cmd_validate(a):
    problems = []
    agents, skills = common.load_agents(), common.load_skills()
    ed = common.evals_dir()
    seen = set()
    tasks = suites.load_routing_tasks()
    per_agent = {}
    for t in tasks:
        tid = t.get("id", "?")
        for f in ("id", "agent", "fixture", "prompt", "why_hard", "grader", "gold", "bad"):
            if not t.get(f):
                problems.append("%s: missing %s" % (tid, f))
        if tid in seen:
            problems.append("%s: duplicate id" % tid)
        seen.add(tid)
        if t.get("agent") not in agents:
            problems.append("%s: agent %s not in agents/" % (tid, t.get("agent")))
        per_agent[t.get("agent")] = per_agent.get(t.get("agent"), 0) + 1
        fx = os.path.join(ed, "fixtures", str(t.get("fixture")))
        if not os.path.isdir(fx):
            problems.append("%s: fixture %s missing" % (tid, t.get("fixture")))
            continue
        for label, want in (("gold", True), ("bad", False), ("blank", False)):
            ws = runner.make_workspace(fx)
            try:
                spec = t.get(label) or {"text": ""}
                if label == "blank":
                    spec = {"text": ""}
                for rel, content in (spec.get("files") or {}).items():
                    p = os.path.join(ws, rel)
                    os.makedirs(os.path.dirname(p), exist_ok=True)
                    open(p, "w").write(content)
                (ok, detail), flaky = graders.grade_twice(t["grader"], {"output": spec.get("text", ""), "workspace": ws, "fixture": fx})
                if ok != want:
                    problems.append("%s: grader says %s for the %s answer (%s)" % (tid, "pass" if ok else "fail", label, detail))
                if flaky:
                    problems.append("%s: grader is not deterministic on the %s answer" % (tid, label))
            finally:
                shutil.rmtree(ws, ignore_errors=True)
        if os.path.abspath(os.path.join(ed, "tasks")).startswith(os.path.abspath(os.path.join(ed, "fixtures"))):
            problems.append("answer keys are inside the fixtures folder")
    trig = common.read_json(os.path.join(ed, "triggers.json"), {}).get("skills", {})
    for s in sorted(skills):
        t = trig.get(s)
        if not t or len(t.get("should", [])) < 6 or len(t.get("should_not", [])) < 6:
            problems.append("skill %s: needs 6 should and 6 should_not trigger prompts" % s)
    for s in trig:
        if s not in skills:
            problems.append("triggers.json names unknown skill %s" % s)
    out("tasks: %d across %d agents (%s)" % (len(tasks), len(per_agent), ", ".join("%s %d" % kv for kv in sorted(per_agent.items()))))
    out("trigger sets: %d skills" % len(trig))
    if problems:
        for p in problems:
            out("PROBLEM: " + p)
        return 1
    out("OK: every task passes its gold answer, fails its bad answer and fails a blank answer.")
    return 0


def main(argv):
    ap = argparse.ArgumentParser(prog="mogger-eval.sh", add_help=True)
    sub = ap.add_subparsers(dest="cmd")

    def common_opts(p, run=False):
        p.add_argument("--suite", default="all")
        p.add_argument("--repeats", type=int, default=3)
        p.add_argument("--jobs", type=int, default=int(os.environ.get("MOGGER_EVAL_JOBS", "3")))
        p.add_argument("--agents", default="")
        p.add_argument("--skills", default="")
        p.add_argument("--no-effort-grid", action="store_true")
        if run:
            p.add_argument("--budget", default=None)
            p.add_argument("--background", action="store_true")

    p = sub.add_parser("estimate")
    common_opts(p)
    p = sub.add_parser("consent")
    p.add_argument("--budget", default=None)
    p.add_argument("--note", default="")
    p.add_argument("--revoke", action="store_true")
    p = sub.add_parser("run")
    common_opts(p, True)
    sub.add_parser("status")
    sub.add_parser("report")
    sub.add_parser("validate")
    p = sub.add_parser("hillclimb")
    p.add_argument("--skill", required=True)
    p.add_argument("--rounds", type=int, default=3)
    p.add_argument("--repeats", type=int, default=3)
    p.add_argument("--jobs", type=int, default=int(os.environ.get("MOGGER_EVAL_JOBS", "3")))
    p.add_argument("--budget", default=None)
    p.add_argument("--min-gain", type=float, default=0.10)
    p.add_argument("--force", action="store_true")
    p.add_argument("--background", action="store_true")
    p = sub.add_parser("ab")
    asub = p.add_subparsers(dest="ab_cmd")
    for name in ("estimate", "plan", "run"):
        q = asub.add_parser(name)
        q.add_argument("--model", default=None)
        q.add_argument("--effort", default=None)
        q.add_argument("--repeats", type=int, default=None)
        q.add_argument("--tasks", default="")
        q.add_argument("--set", default=ab.DEFAULT_SET, choices=ab.ALL_SETS)
        q.add_argument("--suite", default="all", choices=["build", "safety", "all"])
        q.add_argument("--build-repeats", type=int, default=None)
        q.add_argument("--safety-repeats", type=int, default=None)
        q.add_argument("--jobs", type=int, default=int(os.environ.get("MOGGER_AB_JOBS", str(ab.DEFAULT_JOBS))))
        q.add_argument("--seed", default=os.environ.get("MOGGER_AB_SEED", ab.DEFAULT_SEED))
        if name == "run":
            q.add_argument("--budget", default=None)
            q.add_argument("--trial-cap", default=None)
            q.add_argument("--background", action="store_true")
    q = asub.add_parser("status")
    q.add_argument("--set", default=None, choices=ab.ALL_SETS)
    q.add_argument("--suite", default="all", choices=["build", "safety", "all"])
    q = asub.add_parser("validate")
    q.add_argument("--set", default=ab.DEFAULT_SET, choices=ab.ALL_SETS)
    q.add_argument("--suite", default="all", choices=["build", "safety", "all"])
    q = asub.add_parser("report")
    q.add_argument("--input", default=None)
    q.add_argument("--set", default=None, choices=ab.ALL_SETS)
    q.add_argument("--suite", default="all", choices=["build", "safety", "all"])
    q.add_argument("--seed", default=ab.DEFAULT_SEED)
    p = sub.add_parser("apply")
    p.add_argument("proposal")
    p.add_argument("--yes", action="store_true")
    p.add_argument("--force", action="store_true")
    p.add_argument("--target", default=None)
    a = ap.parse_args(argv)
    if a.cmd is None:
        ap.print_help()
        return 2
    for k in ("repeats", "jobs", "build_repeats", "safety_repeats"):
        v = getattr(a, k, None)
        if v is not None and v < 1:
            common.die("--repeats and --jobs must be 1 or more")
    return {"estimate": cmd_estimate, "consent": cmd_consent, "run": cmd_run, "status": cmd_status,
            "report": cmd_report, "hillclimb": cmd_hillclimb, "apply": cmd_apply, "validate": cmd_validate,
            "ab": lambda x: ab.main(x, out, read_consent)}[a.cmd](a)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
