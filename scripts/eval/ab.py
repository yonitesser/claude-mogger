"""A/B benchmark: does installing mogger make a real project cheaper or more expensive,
and does it change how often the task is done correctly?  (`mogger-eval.sh ab ...`)

Two arms run the SAME tasks in fresh temp copies of the SAME fixture with the SAME model,
effort, prompt, tool permissions and turn limit:
  plain   Claude Code with no mogger (no --plugin-dir; user settings excluded).
  mogger  the same, plus this plugin through --plugin-dir, hooks active.

Stdlib only. No network of its own. The only model calls are the trials of `ab run`;
`estimate`, `plan`, `status`, `report` and `validate` never call the model.
Dollar figures: the CLI's total_cost_usd is a client-side estimate, not a bill.
"""
import ast
import hashlib
import json
import math
import os
import random
import re
import shutil
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor

import common
import graders
import runner

ARMS = ("plain", "mogger")
DEFAULT_MODEL = "sonnet"
DEFAULT_REPEATS = 3
DEFAULT_JOBS = 2
DEFAULT_SEED = "mogger-ab-v1"
MIN_PAIRS = 6          # fewer valid pairs than this: no claim at all
BOOT_N = 2000

# ----------------------------------------------------------------------------------
# ONE tunable table for `estimate`. All values are ASSUMPTIONS, chosen on the high side
# (pessimistic). Input tokens are NOT discounted for prompt caching, so real cost should
# come out lower. Change them here or with the env vars named in est_table().
# ----------------------------------------------------------------------------------
AB_EST = {
    "in_tokens": 150000,            # input tokens per trial (context re-sent every turn, no cache discount)
    "out_tokens": 8000,             # output tokens per trial
    "secs": 120,                    # wall seconds per trial
    "arm_b_extra_in_tokens": 15000, # mogger adds hook output and descriptions to the context, every turn
    "trial_cap_factor": 2.0,        # --max-budget-usd per trial = factor x the larger arm estimate ...
    "trial_cap_min_usd": 0.50,      # ... but never below this
}
EST_ENV = {"in_tokens": "MOGGER_AB_EST_IN", "out_tokens": "MOGGER_AB_EST_OUT", "secs": "MOGGER_AB_EST_SECS",
           "arm_b_extra_in_tokens": "MOGGER_AB_EST_EXTRA_IN", "trial_cap_min_usd": "MOGGER_AB_TRIAL_CAP_MIN"}

# Tools both arms may use without a prompt. Edits come from --permission-mode acceptEdits.
ALLOWED_TOOLS = ["Read", "Edit", "Write", "Glob", "Grep", "Bash(python3 *)", "Bash(python *)", "Bash(ls *)",
                 "Bash(cat *)", "Bash(grep *)", "Bash(wc *)", "Bash(head *)", "Bash(tail *)", "Bash(sed *)",
                 "Bash(find *)", "Bash(git status*)", "Bash(git diff*)", "Bash(git log*)"]
DENIED_TOOLS = ["WebFetch", "WebSearch"]

PLUGIN_COPY_DIRS = (".claude-plugin", "skills", "agents", "hooks", "templates", "scripts")

HEADER = [
    "mogger A/B benchmark: does mogger change cost and correctness on small real tasks?",
    "ARM plain = Claude Code, no plugin. ARM mogger = the same plus this plugin (--plugin-dir, hooks on).",
    "Both arms: same model, effort, prompt, fixture copy, turn limit, tools. Trials run in fresh temp copies",
    "with a one-commit git history. Answer keys are outside the workspace. Arm order is seeded and random.",
    "",
    "VERIFIED against the docs (read 2026-10-02; claude --help of v2.1.287):",
    "  -p, --output-format stream-json (needs --verbose), --include-hook-events, --model, --effort, --max-turns,",
    "  --max-budget-usd, --permission-mode acceptEdits, --allowedTools / --disallowedTools (space separated rules),",
    "  --setting-sources, --strict-mcp-config, --no-session-persistence, --plugin-dir, --settings.",
    "  Result event: total_cost_usd (client-side estimate), usage, num_turns, duration_ms, is_error, subtype.",
    "  system/init has claude_code_version and plugins[]; hook_started / hook_response events carry hook_event and hook_name.",
    "  Env CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 and CLAUDE_CODE_DISABLE_CLAUDE_MDS=1 (set in both arms).",
    "  URLs: https://code.claude.com/docs/en/headless  /cli-reference  /plugins/create  /env-vars  /agent-sdk/typescript",
    "ASSUMED (not proven against a live API):",
    "  * --setting-sources project keeps the user's own plugins, hooks and settings out of BOTH arms. Managed",
    "    settings still apply. ~/.claude CLAUDE.md is disabled by the env var above (documented).",
    "  * Plugin hooks run under --permission-mode acceptEdits (hooks are not part of permission modes in the docs).",
    "    If the report shows no hook events in arm B, treat arm B as having NO mogger enforcement.",
    "  * Plugin hooks appear as hook_started / hook_response events; the script name is read from any '.../scripts/NAME.sh'",
    "    text in the event, otherwise the hook_name is used.",
    "  * --bare is NOT used: it skips hooks and needs an API key (docs), which would remove what arm B tests.",
    "SAFETY: acceptEdits does not sandbox. Trials let the model run python3, grep and similar commands in a temp",
    "  folder as YOU, with no prompt. Network tools and package installs are not pre-approved. Run it on a machine you trust.",
]


def est_table():
    t = dict(AB_EST)
    for k, env in EST_ENV.items():
        v = os.environ.get(env)
        if v:
            try:
                t[k] = float(v)
            except ValueError:
                common.die("%s must be a number" % env)
    return t


# ------------------------------------------------------------------ paths and loading
def ab_dir():
    return os.path.join(common.evals_dir(), "ab")


def ab_state():
    d = os.path.join(common.state_dir(), "ab")
    os.makedirs(d, exist_ok=True)
    return d


def load_tasks(filt=None):
    d = common.read_json(os.path.join(ab_dir(), "tasks.json"), {}) or {}
    tasks = list(d.get("tasks", []))
    if filt:
        by = {}
        for t in tasks:
            by[t["id"]] = t
            by[t["id"][3:] if t["id"].startswith("ab-") else t["id"]] = t
        picked, seen = [], set()
        for f in filt:
            if f not in by:
                common.die("Unknown task %r. Known: %s" % (f, ", ".join(t["id"] for t in tasks)))
            if by[f]["id"] not in seen:
                seen.add(by[f]["id"])
                picked.append(by[f])
        tasks = picked
    return tasks


def fixture_dir(task):
    return os.path.join(ab_dir(), "fixtures", task["fixture"])


def keys_dir(task):
    return os.path.join(ab_dir(), "keys", task["id"])


def plugin_version():
    d = common.read_json(os.path.join(common.plugin_root(), ".claude-plugin", "plugin.json"), {}) or {}
    return str(d.get("version", "unknown"))


# ------------------------------------------------------------------ graders (registered into graders.GRADERS)
def read_tree(root):
    out = {}
    for dp, dns, fns in os.walk(root):
        dns[:] = [d for d in dns if d not in ("__pycache__", ".git")]
        for fn in fns:
            p = os.path.join(dp, fn)
            try:
                with open(p) as f:
                    out[os.path.relpath(p, root)] = f.read()
            except (OSError, UnicodeDecodeError):
                pass
    return out


def apply_tree(root, files):
    for rel, content in files.items():
        p = os.path.join(root, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w") as f:
            f.write(content)


def _g_ab_run(spec, ctx):
    overlay = {}
    if spec.get("hidden"):
        overlay = read_tree(os.path.join(ctx["keys_dir"], "hidden"))
    s = {"cmd": spec["cmd"], "overlay": overlay, "min_tests": spec.get("min_tests"), "timeout": spec.get("timeout", 90)}
    ok, detail = graders._g_run(s, ctx)
    return ok, ("hidden tests: " if spec.get("hidden") else "suite: ") + detail


FALLBACK_STDLIB = frozenset("""abc argparse array ast asyncio base64 binascii bisect builtins calendar collections contextlib
copy csv ctypes dataclasses datetime decimal difflib enum errno fnmatch fractions functools glob gzip hashlib heapq hmac html
http importlib inspect io itertools json logging math operator os pathlib pickle platform pprint queue random re secrets shlex
shutil signal socket sqlite3 statistics string struct subprocess sys tempfile textwrap threading time traceback types typing
unittest urllib uuid warnings weakref xml zipfile zlib __future__""".split())


def stdlib_names():
    s = getattr(sys, "stdlib_module_names", None)
    return frozenset(s) if s else FALLBACK_STDLIB


def norm_pkg(name):
    return re.sub(r"[-_.]+", "-", name.strip().lower())


def req_names(path):
    names = set()
    try:
        lines = open(path).read().split("\n")
    except OSError:
        return names
    for ln in lines:
        ln = ln.split("#")[0].strip()
        if not ln or ln.startswith("-"):
            continue
        n = re.split(r"[<>=!~;\[ @]", ln)[0]
        if n:
            names.add(norm_pkg(n))
    return names


def _g_ab_deps(spec, ctx):
    ws, fx = ctx["workspace"], ctx["fixture"]
    reg = req_names(os.path.join(fx, spec["registry"]))
    allowed_new = set(norm_pkg(x) for x in spec.get("allowed_new", []))
    mods = dict((norm_pkg(k), v) for k, v in (spec.get("module_names") or {}).items())
    reg_mods = set(mods.get(r, r.replace("-", "_")) for r in reg)
    problems = []
    new = req_names(os.path.join(ws, spec["requirements"])) - req_names(os.path.join(fx, spec["requirements"]))
    for n in sorted(new):
        if n not in reg:
            problems.append("%s is not in %s" % (n, spec["registry"]))
        elif n not in allowed_new:
            problems.append("%s is on the mirror but not needed" % n)
    local = set()
    for name in os.listdir(ws):
        if name.startswith("."):
            continue
        local.add(name[:-3] if name.endswith(".py") else name)
    std = stdlib_names()
    for dp, dns, fns in os.walk(ws):
        dns[:] = [d for d in dns if not d.startswith(".") and d != "__pycache__"]
        for fn in fns:
            if not fn.endswith(".py"):
                continue
            try:
                tree = ast.parse(open(os.path.join(dp, fn)).read())
            except (SyntaxError, OSError, ValueError):
                continue
            for node in ast.walk(tree):
                tops = []
                if isinstance(node, ast.Import):
                    tops = [a.name.split(".")[0] for a in node.names]
                elif isinstance(node, ast.ImportFrom) and node.level == 0 and node.module:
                    tops = [node.module.split(".")[0]]
                for m in tops:
                    if m not in std and m not in local and m not in reg_mods:
                        problems.append("%s imports %s (not stdlib, not local, not in the registry)" % (fn, m))
    for dp, dns, fns in os.walk(ws):
        dns[:] = [d for d in dns if not d.startswith(".") and d != "__pycache__"]
        for fn in fns:
            rel = os.path.relpath(os.path.join(dp, fn), ws)
            if fn in ("package.json", "pyproject.toml", "Pipfile", "setup.py", "setup.cfg") and not os.path.exists(os.path.join(fx, rel)):
                problems.append("new package manifest %s" % rel)
    problems = sorted(set(problems))
    return (not problems, "dependencies: " + ("; ".join(problems) if problems else "only approved, needed packages"))


def _g_ab_no_secret(spec, ctx):
    ws = ctx["workspace"]
    pats = [re.compile(p) for p in spec.get("patterns", [])]
    hits = []
    for dp, dns, fns in os.walk(ws):
        dns[:] = [d for d in dns if d not in (".git", ".claude", "__pycache__", "node_modules")]
        for fn in fns:
            p = os.path.join(dp, fn)
            try:
                with open(p, "rb") as f:
                    text = f.read().decode("utf-8", "replace")
            except OSError:
                continue
            rel = os.path.relpath(p, ws)
            for v in spec.get("values", []):
                if v and v in text:
                    hits.append("%s holds the secret (%s...)" % (rel, v[:6]))
            for rx in pats:
                if rx.search(text):
                    hits.append("%s matches a secret pattern" % rel)
    hits = sorted(set(hits))
    return (not hits, "secret check: " + ("; ".join(hits) if hits else "no secret literal in any file"))


graders.GRADERS["ab_run"] = _g_ab_run
graders.GRADERS["ab_deps"] = _g_ab_deps
graders.GRADERS["ab_no_secret"] = _g_ab_no_secret


# ------------------------------------------------------------------ plan (seeded, interleaved)
def arm_order(seed, task_id, repeat):
    """Seeded random order of the two arms for one (task, repeat). Same inputs, same order."""
    def h(arm):
        return hashlib.sha256(("%s|%s|%d|%s" % (seed, task_id, repeat, arm)).encode()).hexdigest()
    return sorted(ARMS, key=h)


def build_plan(tasks, repeats, seed):
    """Repeat-major, then task, then the two arms back to back. A run cut short at any point still
    has every task in both arms for all earlier repeats (a fair partial result)."""
    plan = []
    for r in range(1, repeats + 1):
        for t in tasks:
            for arm in arm_order(seed, t["id"], r):
                plan.append({"task": t, "arm": arm, "repeat": r})
    return plan


def plan_digest(plan):
    s = "\n".join("%s|%d|%s" % (p["task"]["id"], p["repeat"], p["arm"]) for p in plan)
    return hashlib.sha256(s.encode()).hexdigest()[:12]


# ------------------------------------------------------------------ estimate (NO model calls)
def trial_est_usd(arm, model, tbl=None):
    t = tbl or est_table()
    extra = t["arm_b_extra_in_tokens"] if arm == "mogger" else 0
    return common.token_cost(common.tier_of(model), t["in_tokens"] + extra, t["out_tokens"])


def trial_cap_usd(model, tbl=None):
    t = tbl or est_table()
    worst = max(trial_est_usd(a, model, t) for a in ARMS)
    return round(max(t["trial_cap_min_usd"], t["trial_cap_factor"] * worst), 2)


def build_estimate(tasks, repeats, jobs, model):
    t = est_table()
    n_tasks = len(tasks)
    per_arm = {}
    for arm in ARMS:
        runs = n_tasks * repeats
        per_arm[arm] = {"runs": runs, "usd": runs * trial_est_usd(arm, model, t)}
    runs = sum(v["runs"] for v in per_arm.values())
    usd = sum(v["usd"] for v in per_arm.values())
    return {"runs": runs, "usd": usd, "per_arm": per_arm, "minutes": runs * t["secs"] / max(jobs, 1) / 60.0,
            "trial_cap_usd": trial_cap_usd(model, t), "table": t}


# ------------------------------------------------------------------ one trial
def make_plugin_copy(root):
    """Plugin copy for arm B: the plugin as shipped (manifest, skills, agents, hooks, templates, scripts) and
    nothing else. evals/ (answer keys) and tests/ are left out so the model cannot read them."""
    dst = _mkdtemp("mogger-ab-plugin-")
    for d in PLUGIN_COPY_DIRS:
        s = os.path.join(root, d)
        if os.path.isdir(s):
            shutil.copytree(s, os.path.join(dst, d), ignore=shutil.ignore_patterns("__pycache__", ".git"))
    return dst


def _mkdtemp(prefix):
    import tempfile
    return tempfile.mkdtemp(prefix=prefix)


def deny_settings():
    """Same JSON in both arms. Best effort: keeps Read/Grep/Glob out of the evals folder."""
    rules = []
    for base in sorted(set([common.evals_dir(), os.path.join(common.plugin_root(), "evals")])):
        for tool in ("Read", "Grep", "Glob"):
            rules.append("%s(/%s/**)" % (tool, base.lstrip("/")))
    return json.dumps({"permissions": {"deny": rules}})


def setting_sources():
    return os.environ.get("MOGGER_EVAL_SETTING_SOURCES", "project")


def build_cmd(task, arm, model, effort, plugin_dir, cap_usd):
    cmd = [common.claude_bin(), "-p", task["prompt"], "--output-format", "stream-json", "--verbose",
           "--include-hook-events", "--model", model]
    if effort and effort != "default":
        cmd += ["--effort", effort]
    cmd += ["--permission-mode", "acceptEdits", "--no-session-persistence", "--strict-mcp-config",
            "--max-turns", str(task.get("max_turns", 30)), "--max-budget-usd", "%.2f" % cap_usd,
            "--settings", deny_settings(), "--disallowedTools"] + DENIED_TOOLS
    cmd += ["--allowedTools"] + ALLOWED_TOOLS
    src = setting_sources()
    if src:
        cmd += ["--setting-sources", src]
    if arm == "mogger":
        cmd += ["--plugin-dir", plugin_dir]
    extra = os.environ.get("MOGGER_EVAL_EXTRA_ARGS", "").strip()
    return cmd + (extra.split() if extra else [])


def child_env(task_id, repeat):
    env = dict(os.environ)
    env["MOGGER_EVAL_TASK_ID"] = task_id
    env["MOGGER_EVAL_TRIAL"] = str(repeat)
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    env["CLAUDE_CODE_DISABLE_AUTO_MEMORY"] = "1"
    env["CLAUDE_CODE_DISABLE_CLAUDE_MDS"] = "1"
    return env


SCRIPT_RE = re.compile(r"scripts/([A-Za-z0-9_.-]+\.sh)")


def parse_trial_stream(lines):
    """Everything measured from one stream-json transcript."""
    info = runner.parse_stream(lines)
    out = {"info": info, "hooks": {}, "hook_events": 0, "plugins": None, "cli_version": "", "init_seen": False}
    seen_ids = set()
    for raw in lines:
        raw = raw.strip()
        if not raw or raw[0] != "{":
            continue
        try:
            ev = json.loads(raw)
        except Exception:
            continue
        if ev.get("type") != "system":
            continue
        st = ev.get("subtype")
        if st == "init":
            out["init_seen"] = True
            if isinstance(ev.get("plugins"), list):
                out["plugins"] = [str(p.get("name", "")) if isinstance(p, dict) else str(p) for p in ev["plugins"]]
            out["cli_version"] = str(ev.get("claude_code_version") or "")
        elif st in ("hook_started", "hook_response"):
            out["hook_events"] += 1
            hid = ev.get("hook_id")
            if hid is not None:
                if hid in seen_ids:
                    continue      # count a hook once, at its first event
                seen_ids.add(hid)
            m = SCRIPT_RE.search(raw)
            name = m.group(1) if m else str(ev.get("hook_name") or ev.get("hook_event") or "unknown")
            key = "%s %s" % (ev.get("hook_event") or "?", name)
            out["hooks"][key] = out["hooks"].get(key, 0) + 1
    return out


def usage_of(result):
    u = (result or {}).get("usage") or {}
    g = lambda k: int(u.get(k) or 0)
    return {"input": g("input_tokens"), "output": g("output_tokens"),
            "cache_read": g("cache_read_input_tokens"), "cache_creation": g("cache_creation_input_tokens")}


def run_trial(task, arm, repeat, model, effort, plugin_dir, run_dir, cap_usd, budget_left, cli_version=""):
    ws = runner.make_workspace(fixture_dir(task))
    t0 = time.time()
    try:
        cap = min(cap_usd, max(budget_left, 0.01))
        cmd = build_cmd(task, arm, model, effort, plugin_dir, cap)
        timeout = int(os.environ.get("MOGGER_AB_TIMEOUT") or task.get("timeout", 600))
        lines, rc, timed_out, _, err = runner.run_claude(cmd, ws, child_env(task["id"], repeat), timeout)
        parsed = parse_trial_stream(lines)
        info = parsed["info"]
        want_text = bool(task.get("answer_in_text"))
        status, note = runner.classify(info, timed_out, rc, err, want_text=want_text)
        cost, csrc = runner.cost_of(info, common.tier_of(model))
        r = info["result"] or {}
        wall = time.time() - t0
        dur = (float(r["duration_ms"]) / 1000.0) if isinstance(r.get("duration_ms"), (int, float)) else wall
        rec = {"task": task["id"], "arm": arm, "repeat": repeat, "status": status, "note": note, "passed": None, "detail": "",
               "grader_flaky": False, "cost_usd": cost, "cost_source": csrc, "tokens": usage_of(r),
               "turns": int(r.get("num_turns") or 0), "duration_s": round(dur, 1), "wall_s": round(wall, 1),
               "is_error": bool(r.get("is_error")) if r else None, "subtype": r.get("subtype") or "",
               "hooks": parsed["hooks"], "hook_events": parsed["hook_events"], "plugins": parsed["plugins"],
               "init_seen": parsed["init_seen"], "cli_version": parsed["cli_version"] or cli_version, "cap_usd": cap}
        if status == "ok":
            ctx = {"output": info["text"], "workspace": ws, "fixture": fixture_dir(task), "keys_dir": keys_dir(task)}
            (ok, detail), flaky = graders.grade_twice(task["grader"], ctx)
            rec.update(passed=bool(ok), detail=detail, grader_flaky=flaky)
        rec["transcript"] = runner._save_transcript(run_dir, "%s__%s__%d" % (task["id"], arm, repeat), lines,
                                                    {"task": task["id"], "arm": arm, "repeat": repeat, "status": status})
        return rec
    finally:
        shutil.rmtree(ws, ignore_errors=True)


# ------------------------------------------------------------------ hard spend cap
class Cap:
    """Hard total cap. A trial starts only if spent + in-flight estimates + its own estimate stay within the cap.
    Once one trial is refused, no later trial starts (sticky), so a partial run is a clean prefix of the plan."""

    def __init__(self, budget):
        self.budget = float(budget)
        self.spent = 0.0
        self.inflight = 0.0
        self.stopped = False
        self.lock = threading.Lock()

    def try_start(self, est):
        with self.lock:
            if self.stopped:
                return False
            if self.spent + self.inflight >= self.budget or self.spent + self.inflight + est > self.budget + 1e-12:
                self.stopped = True
                return False
            self.inflight += est
            return True

    def left(self):
        with self.lock:
            return self.budget - self.spent - self.inflight

    def finish(self, est, cost):
        with self.lock:
            self.inflight -= est
            self.spent += cost
            if self.spent >= self.budget:
                self.stopped = True


def execute(plan, cap, jobs, fn, model, log, on_done=None):
    """Runs the plan in order with `jobs` workers. fn(item, budget_left) -> record."""
    records, skipped, lock = [], [0], threading.Lock()
    total = len(plan)

    def work(item):
        est = trial_est_usd(item["arm"], model)
        if not cap.try_start(est):
            with lock:
                skipped[0] += 1
            return
        try:
            rec = fn(item, cap.left() + est)
        except Exception as e:  # a crashed trial is plumbing, never a quality result
            rec = {"task": item["task"]["id"], "arm": item["arm"], "repeat": item["repeat"], "status": "api_error",
                   "note": "runner crashed: %s" % e, "passed": None, "cost_usd": 0.0, "turns": 0, "tokens": {}, "hooks": {}}
        cap.finish(est, rec.get("cost_usd", 0.0))
        with lock:
            records.append(rec)
            verdict = {True: "pass", False: "fail", None: rec.get("status", "?")}[rec.get("passed")]
            log("[%d/%d] %s %s #%d %s $%.4f (spent $%.2f of $%.2f)" % (len(records), total, rec["task"], rec["arm"], rec["repeat"],
                                                                    verdict, rec.get("cost_usd", 0.0), cap.spent, cap.budget))
            if on_done:
                on_done(records, skipped[0])

    with ThreadPoolExecutor(max_workers=max(1, jobs)) as ex:
        list(ex.map(work, plan))
    return records, skipped[0]


# ------------------------------------------------------------------ statistics
def _rng(seed, salt):
    return random.Random(int(hashlib.sha256(("%s|%s" % (seed, salt)).encode()).hexdigest()[:12], 16))


def percentile(sorted_vals, q):
    """Linear-interpolated percentile, q in [0, 100]."""
    if not sorted_vals:
        return None
    if len(sorted_vals) == 1:
        return sorted_vals[0]
    pos = (len(sorted_vals) - 1) * q / 100.0
    lo = int(math.floor(pos))
    hi = int(math.ceil(pos))
    return sorted_vals[lo] + (sorted_vals[hi] - sorted_vals[lo]) * (pos - lo)


def ci95(draws):
    d = sorted(x for x in draws if x is not None)
    if len(d) < 20:
        return None
    return (percentile(d, 2.5), percentile(d, 97.5))


def is_valid(t):
    return t.get("status") == "ok" and t.get("passed") is not None


def cost_per_success(total_cost, k):
    return (total_cost / k) if k > 0 else None


def pair_stats(sample):
    """sample: list of pair dicts. Returns (relative change in cost per successful task, mean cost diff per trial,
    success-rate difference over pairs where both trials were scorable)."""
    ca = sum(p["a_cost"] for p in sample)
    cb = sum(p["b_cost"] for p in sample)
    ka = sum(p["a_succ"] for p in sample)
    kb = sum(p["b_succ"] for p in sample)
    ratio = None
    if ka > 0 and kb > 0 and ca > 0:
        ratio = (cb / kb) / (ca / ka) - 1.0
    cdiff = (cb - ca) / len(sample) if sample else None
    both = [p for p in sample if p["a_valid"] and p["b_valid"]]
    sdiff = (sum(p["b_succ"] - p["a_succ"] for p in both) / float(len(both))) if both else None
    return ratio, cdiff, sdiff


def make_pairs(trials):
    by = {}
    for t in trials:
        by.setdefault((t["task"], t["repeat"]), {})[t["arm"]] = t
    pairs = []
    for (task, rep), d in sorted(by.items()):
        if "plain" in d and "mogger" in d:
            a, b = d["plain"], d["mogger"]
            pairs.append({"task": task, "repeat": rep,
                          "a_cost": float(a.get("cost_usd") or 0.0), "b_cost": float(b.get("cost_usd") or 0.0),
                          "a_valid": is_valid(a), "b_valid": is_valid(b),
                          "a_succ": 1 if (is_valid(a) and a["passed"]) else 0,
                          "b_succ": 1 if (is_valid(b) and b["passed"]) else 0})
    return pairs


def paired_bootstrap(pairs, seed, n_boot=BOOT_N):
    """Stratified (within task) paired bootstrap. Tasks are a fixed design, not a sample of tasks, so each task keeps
    its pair count; pairs inside a task are resampled with replacement. Same seed, same answer."""
    point = pair_stats(pairs)
    strata = {}
    for p in pairs:
        strata.setdefault(p["task"], []).append(p)
    rng = _rng(seed, "paired")
    draws = [[], [], []]
    keys = sorted(strata)
    for _ in range(n_boot):
        sample = []
        for k in keys:
            grp = strata[k]
            for _i in range(len(grp)):
                sample.append(grp[rng.randrange(len(grp))])
        s = pair_stats(sample)
        for i in range(3):
            draws[i].append(s[i])
    return {"point": {"rel_cost_per_success": point[0], "cost_diff_per_trial": point[1], "success_diff": point[2]},
            "ci": {"rel_cost_per_success": ci95(draws[0]), "cost_diff_per_trial": ci95(draws[1]), "success_diff": ci95(draws[2])},
            "n_pairs": len(pairs), "n_boot": n_boot}


def arm_bootstrap(trials, seed, arm, n_boot=BOOT_N):
    """Per arm: CI for mean cost per trial and for cost per successful task. Resamples trials within each task."""
    strata = {}
    for t in trials:
        strata.setdefault(t["task"], []).append(t)
    rng = _rng(seed, "arm-" + arm)
    keys = sorted(strata)
    means, cps = [], []
    for _ in range(n_boot):
        cost, k, n = 0.0, 0, 0
        for key in keys:
            grp = strata[key]
            for _i in range(len(grp)):
                t = grp[rng.randrange(len(grp))]
                cost += float(t.get("cost_usd") or 0.0)
                n += 1
                if is_valid(t) and t["passed"]:
                    k += 1
        means.append(cost / n if n else None)
        cps.append(cost_per_success(cost, k))
    return ci95(means), ci95(cps)


def cell(trials):
    valid = [t for t in trials if is_valid(t)]
    k = sum(1 for t in valid if t["passed"])
    n = len(valid)
    plumb = {}
    for t in trials:
        if not is_valid(t):
            s = t.get("status", "?")
            plumb[s] = plumb.get(s, 0) + 1
    costs = [float(t.get("cost_usd") or 0.0) for t in trials]
    turns = [t.get("turns", 0) for t in trials if t.get("turns")]
    lo, hi = common.wilson(k, n)
    return {"trials": len(trials), "n": n, "k": k, "rate": (float(k) / n if n else None), "ci95": [lo, hi],
            "plumbing": plumb, "plumbing_n": sum(plumb.values()), "total_cost": sum(costs),
            "mean_cost": common.mean(costs) if costs else None, "mean_turns": common.mean(turns) if turns else None,
            "mean_duration_s": common.mean([t.get("duration_s", 0) for t in trials]) if trials else None}


def tok_total(t):
    k = t.get("tokens") or {}
    return int(k.get("input", 0)) + int(k.get("cache_read", 0)) + int(k.get("cache_creation", 0))


def analyze(trials, seed=DEFAULT_SEED, n_boot=BOOT_N, partial=False):
    arms, per_task = {}, {}
    for arm in ARMS:
        ts = [t for t in trials if t.get("arm") == arm]
        c = cell(ts)
        c["cost_per_success"] = cost_per_success(c["total_cost"], c["k"])
        if ts:
            c["mean_cost_ci95"], c["cost_per_success_ci95"] = arm_bootstrap(ts, seed, arm, n_boot)
        else:
            c["mean_cost_ci95"], c["cost_per_success_ci95"] = None, None
        c["mean_input_tokens"] = common.mean([tok_total(t) for t in ts]) if ts else None
        c["mean_output_tokens"] = common.mean([(t.get("tokens") or {}).get("output", 0) for t in ts]) if ts else None
        arms[arm] = c
    for task in sorted(set(t["task"] for t in trials)):
        per_task[task] = {arm: cell([t for t in trials if t["task"] == task and t["arm"] == arm]) for arm in ARMS}
    pairs = make_pairs(trials)
    paired = paired_bootstrap(pairs, seed, n_boot) if pairs else None
    valid_pairs = sum(1 for p in pairs if p["a_valid"] and p["b_valid"])
    return {"arms": arms, "tasks": per_task, "paired": paired, "valid_pairs": valid_pairs, "n_pairs": len(pairs),
            "unpaired_trials": len(trials) - 2 * len(pairs), "verdict": verdict(arms, paired, valid_pairs, partial)}


def _spct(x):
    v = int(round(100.0 * x))
    return ("+%d%%" if v > 0 else "%d%%") % v


def verdict(arms, paired, valid_pairs, partial=False):
    """Plain words (ASD-STE100 style). A claim is made only when the interval excludes zero."""
    out = {"cost": "", "success": "", "claim_cost": False, "claim_success": False}
    a, b = arms["plain"], arms["mogger"]
    if paired is None or valid_pairs < MIN_PAIRS:
        out["cost"] = "Too few paired results (%d, need %d). No claim." % (valid_pairs, MIN_PAIRS)
        out["success"] = out["cost"]
        return out
    pt, ci = paired["point"], paired["ci"]
    r, rci = pt["rel_cost_per_success"], ci["rel_cost_per_success"]
    if r is None or rci is None or a["k"] == 0 or b["k"] == 0:
        out["cost"] = "One arm had no correct result, so cost per correct task cannot be compared. No claim."
    elif rci[0] > 0 or rci[1] < 0:
        word = "more" if r > 0 else "less"
        out["cost"] = "Mogger cost %d%% %s per successful task (95%% CI %s to %s)." % (
            abs(int(round(100 * r))), word, _spct(rci[0]), _spct(rci[1]))
        out["claim_cost"] = True
    else:
        out["cost"] = ("The difference is within noise: no claim. Seen change, not a claim: %s per successful task "
                       "(95%% CI %s to %s)." % (_spct(r), _spct(rci[0]), _spct(rci[1])))
    s, sci = pt["success_diff"], ci["success_diff"]
    if s is None or sci is None:
        out["success"] = "Not enough scorable pairs to compare correctness. No claim."
    elif sci[0] > 0 or sci[1] < 0:
        out["success"] = "Mogger changed the success rate by %+d points (95%% CI %+d to %+d points)." % (
            int(round(100 * s)), int(round(100 * sci[0])), int(round(100 * sci[1])))
        out["claim_success"] = True
    else:
        out["success"] = ("The success difference is within noise: no claim. Seen change, not a claim: %+d points "
                          "(95%% CI %+d to %+d points)." % (int(round(100 * s)), int(round(100 * sci[0])), int(round(100 * sci[1]))))
    if partial:
        out["cost"] += " PARTIAL RUN: some trials did not happen."
    return out


# ------------------------------------------------------------------ overhead and hooks
def overhead_facts():
    root = common.plugin_root()
    sh = os.path.join(root, "scripts", "context-cost.sh")
    if not os.path.isfile(sh):
        return None
    try:
        env = dict(os.environ, MOGGER_ROOT=root)
        r = subprocess.run(["bash", sh, "--json"], env=env, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=60)
        return json.loads(r.stdout.decode("utf-8", "replace").strip().split("\n")[-1])
    except Exception:
        return None


def hook_summary(trials):
    out = {}
    for arm in ARMS:
        ts = [t for t in trials if t.get("arm") == arm]
        counts = {}
        for t in ts:
            for k, v in (t.get("hooks") or {}).items():
                counts[k] = counts.get(k, 0) + v
        out[arm] = {"trials": len(ts), "trials_with_hook_events": sum(1 for t in ts if t.get("hook_events")),
                    "hook_events": sum(t.get("hook_events", 0) for t in ts), "hooks": counts,
                    "plugin_listed": sum(1 for t in ts if t.get("plugins") and any("mogger" in p.lower() for p in t["plugins"])),
                    "init_seen": sum(1 for t in ts if t.get("init_seen"))}
    return out


def warnings_for(trials, an, hooks, partial):
    w = []
    if partial:
        w.append("PARTIAL RESULTS: the spend cap stopped the run. Some trials did not happen.")
    if not setting_sources():
        w.append("ISOLATION OFF: MOGGER_EVAL_SETTING_SOURCES is empty, so your own plugins and hooks load in BOTH arms.")
    if hooks["plain"]["hook_events"] or hooks["plain"]["plugin_listed"]:
        w.append("ISOLATION BROKEN: the plain arm shows hook events or a mogger plugin. The comparison is not valid.")
    if hooks["mogger"]["trials"] and not hooks["mogger"]["hook_events"]:
        w.append("NO HOOK EVENTS in the mogger arm. Either hooks did not run (acceptEdits and --plugin-dir hooks are "
                 "UNVERIFIED) or this CLI does not emit them. Treat arm B as having NO mogger enforcement.")
    if hooks["mogger"]["init_seen"] and not hooks["mogger"]["plugin_listed"]:
        w.append("The init event of the mogger arm does not list the plugin. Check that --plugin-dir loaded it.")
    pa, pb = an["arms"]["plain"], an["arms"]["mogger"]
    for arm, c in (("plain", pa), ("mogger", pb)):
        if c["trials"] and float(c["plumbing_n"]) / c["trials"] > 0.25:
            w.append("%s arm: %d of %d trials were infrastructure failures (excluded from quality)." % (arm, c["plumbing_n"], c["trials"]))
    if abs(pa["plumbing_n"] - pb["plumbing_n"]) >= 3:
        w.append("The arms have different numbers of infrastructure failures (%d vs %d). Look at the plumbing table before "
                 "trusting the correctness comparison." % (pa["plumbing_n"], pb["plumbing_n"]))
    if any(t.get("grader_flaky") for t in trials):
        w.append("A grader gave two different answers on the same output. Fix the grader first.")
    if an["unpaired_trials"]:
        w.append("%d trial(s) have no partner in the other arm and are left out of the paired statistics." % an["unpaired_trials"])
    return w


# ------------------------------------------------------------------ reports
def money(x):
    return "n/a" if x is None else "$%.4f" % x


def pc(x):
    return "n/a" if x is None else "%d%%" % int(round(100 * x))


def ci_money(ci):
    return "" if not ci else " (95%% CI $%.4f to $%.4f)" % tuple(ci)


def text_lines(res, head=True):
    an, L = res["analysis"], []
    L.append("mogger A/B benchmark (%s)" % res.get("ts", "?"))
    L.append("Model: %s. CLI: %s. Plugin version: %s. Repeats: %s. Seed: %s." % (
        res.get("model"), res.get("cli_version") or "unknown", res.get("plugin_version"), res.get("repeats"), res.get("seed")))
    L.append("All dollar figures are the CLI's client-side ESTIMATE (total_cost_usd), not a bill.")
    L.append("Permission mode acceptEdits. Hooks under that mode are UNVERIFIED: see the hook lines below.")
    if res.get("partial"):
        L.append("PARTIAL RESULTS: %d of %d planned trials ran. The spend cap stopped the run." % (res.get("completed", 0), res.get("planned", 0)))
    L.append("")
    L.append("VERDICT")
    L.append(an["verdict"]["cost"])
    L.append(an["verdict"]["success"])
    L.append("")
    if not head:
        L = []
    for arm in ARMS:
        c = an["arms"][arm]
        L.append("Arm %s: %d trials, %d scored, %d correct (%s, 95%% CI %s to %s). Total cost %s. Cost per successful task %s%s. Mean cost per trial %s%s. Mean turns %s." % (
            arm, c["trials"], c["n"], c["k"], pc(c["rate"]), pc(c["ci95"][0]), pc(c["ci95"][1]), money(c["total_cost"]),
            money(c["cost_per_success"]), ci_money(c.get("cost_per_success_ci95")), money(c["mean_cost"]), ci_money(c.get("mean_cost_ci95")),
            "n/a" if c["mean_turns"] is None else "%.1f" % c["mean_turns"]))
        if c["plumbing_n"]:
            L.append("  Infrastructure failures (not scored, cost counted): %s." % ", ".join("%s %d" % kv for kv in sorted(c["plumbing"].items())))
    p = an["paired"]
    if p:
        pt, ci = p["point"], p["ci"]
        L.append("")
        L.append("Paired difference, mogger minus plain (%d pairs, %d scorable in both arms):" % (an["n_pairs"], an["valid_pairs"]))
        if pt["cost_diff_per_trial"] is not None and ci["cost_diff_per_trial"]:
            L.append("  Mean cost per trial: %+.4f USD (95%% CI %+.4f to %+.4f)." % (pt["cost_diff_per_trial"], ci["cost_diff_per_trial"][0], ci["cost_diff_per_trial"][1]))
        if pt["success_diff"] is not None and ci["success_diff"]:
            L.append("  Success rate: %+d points (95%% CI %+d to %+d)." % (int(round(100 * pt["success_diff"])), int(round(100 * ci["success_diff"][0])), int(round(100 * ci["success_diff"][1]))))
    L.append("")
    L.append("Per task (n scored, correct, mean cost, mean turns):")
    for task, cells in sorted(an["tasks"].items()):
        parts = []
        for arm in ARMS:
            c = cells[arm]
            parts.append("%s %d/%d %s %s turns" % (arm, c["k"], c["n"], money(c["mean_cost"]), "n/a" if c["mean_turns"] is None else "%.1f" % c["mean_turns"]))
        L.append("- %s: %s" % (task, "; ".join(parts)))
    h = res.get("hooks") or {}
    if h:
        L.append("")
        m = h.get("mogger", {})
        L.append("Hooks in the mogger arm: %d hook events in %d of %d trials." % (m.get("hook_events", 0), m.get("trials_with_hook_events", 0), m.get("trials", 0)))
        for k, v in sorted(m.get("hooks", {}).items(), key=lambda kv: -kv[1])[:15]:
            L.append("  %s: %d" % (k, v))
        L.append("Hook events in the plain arm (must be 0): %d." % h.get("plain", {}).get("hook_events", 0))
    ov = res.get("overhead")
    if ov:
        L.append("")
        L.append("Overhead facts (scripts/context-cost.sh, ESTIMATE chars/4): always-on about %s tokens, session start about %s tokens." % (
            ov.get("always_on_tokens"), ov.get("session_start_tokens")))
        if an["arms"]["plain"]["mean_input_tokens"] is not None and an["arms"]["mogger"]["mean_input_tokens"] is not None:
            L.append("Measured: mean input tokens per trial plain %d, mogger %d." % (an["arms"]["plain"]["mean_input_tokens"], an["arms"]["mogger"]["mean_input_tokens"]))
    if res.get("warnings"):
        L.append("")
        L.append("Warnings:")
        for w in res["warnings"]:
            L.append("- " + w)
    return L


METHOD_NOTES = [
    "Tasks 1 and 2 are neutral. Tasks 3 to 6 test features that mogger ships (package check, large-file guard, fix-loop guard, secret guard), so they favour mogger by design. Read the per-task table, not only the total.",
    "A trial is scored only when the run finished with an answer. Timeouts, API errors, max-turns and budget stops are plumbing: not scored, cost still counted.",
    "Cost per successful task = total cost of ALL trials in the arm (wrong and failed ones too) divided by the number of correct trials.",
    "Rates use the Wilson interval (sound at 0% and 100% and for small n). Costs are skewed and success is 0 or 1, so a normal-theory interval fits badly. The CIs for cost use a seeded bootstrap (2000 resamples, within task). The paired difference resamples (task, repeat) pairs, so a hard task hits both arms alike.",
    "A claim is made only when the 95% interval for the paired difference excludes zero. Otherwise the report says: within noise, no claim.",
    "Repeats of one task are not fully independent, so the intervals are somewhat too narrow. Small samples (6 tasks) do not describe your own project.",
    "The task set was written by hand and fixed before any run. It is not tuned on results (no hillclimbing).",
]


def md_report(res):
    L = ["# mogger A/B benchmark", ""]
    L += ["- When: %s" % res.get("ts"), "- Model: %s (effort: %s)" % (res.get("model"), res.get("effort") or "default"),
          "- Claude Code CLI: %s" % (res.get("cli_version") or "unknown"), "- Plugin version: %s" % res.get("plugin_version"),
          "- Repeats: %s, seed: %s, jobs: %s" % (res.get("repeats"), res.get("seed"), res.get("jobs")),
          "- Trials: %s of %s planned%s" % (res.get("completed"), res.get("planned"), " (PARTIAL)" if res.get("partial") else ""),
          "- Spent: $%.4f of a $%.2f cap (client-side estimate from the CLI, not a bill)" % (res.get("spent_usd", 0), res.get("budget_usd", 0)), ""]
    L += ["## Verdict", "", res["analysis"]["verdict"]["cost"], "", res["analysis"]["verdict"]["success"], ""]
    if res.get("warnings"):
        L += ["## Warnings", ""] + ["- " + w for w in res["warnings"]] + [""]
    L += ["## Results", ""] + ["```"] + text_lines(res, False) + ["```", ""]
    L += ["## Method and caveats", ""] + ["- " + n for n in METHOD_NOTES]
    L += ["- Flags and docs that were checked, and what is assumed, are listed in the header of scripts/mogger-eval.sh and printed by `ab plan`.", ""]
    return "\n".join(L)


def html_report(res):
    import html as H
    e = H.escape
    an = res["analysis"]
    rows = []
    for task, cells in sorted(an["tasks"].items()):
        tds = "".join("<td>%d/%d</td><td>%s</td><td>%s</td>" % (cells[a]["k"], cells[a]["n"], money(cells[a]["mean_cost"]),
                      "n/a" if cells[a]["mean_turns"] is None else "%.1f" % cells[a]["mean_turns"]) for a in ARMS)
        rows.append("<tr><th scope=row>%s</th>%s</tr>" % (e(task), tds))
    arm_rows = []
    for arm in ARMS:
        c = an["arms"][arm]
        arm_rows.append("<tr><th scope=row>%s</th><td>%d</td><td>%d/%d (%s)</td><td>%s</td><td>%s</td><td>%s</td></tr>" % (
            arm, c["trials"], c["k"], c["n"], pc(c["rate"]), money(c["total_cost"]), money(c["cost_per_success"]), money(c["mean_cost"])))
    warn = "".join("<li>%s</li>" % e(w) for w in res.get("warnings", []))
    pre = e("\n".join(text_lines(res)))
    notes = "".join("<li>%s</li>" % e(n) for n in METHOD_NOTES)
    return """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>mogger A/B benchmark</title>
<style>
:root{--bg:#fff;--fg:#1c1c1c;--mute:#5a5a5a;--line:#d8d8d8;--warn:#8a4b00}
@media (prefers-color-scheme: dark){:root:not([data-theme="light"]){--bg:#161616;--fg:#e8e8e8;--mute:#a0a0a0;--line:#3a3a3a;--warn:#ffb866}}
body{background:var(--bg);color:var(--fg);font:16px/1.5 system-ui,sans-serif;margin:0;padding:16px;max-width:60rem}
table{border-collapse:collapse;width:100%%;margin:1rem 0;font-size:.9rem}th,td{border:1px solid var(--line);padding:.3rem .5rem;text-align:left}
.wrap{overflow-x:auto}pre{white-space:pre-wrap;overflow-wrap:anywhere;border:1px solid var(--line);padding:.7rem}
.warn{color:var(--warn)}.mute{color:var(--mute)}
</style></head><body>
<h1>mogger A/B benchmark</h1>
<p class="mute">%s. Dollar figures are the CLI's client-side estimate, not a bill.</p>
<h2>Verdict</h2><p><strong>%s</strong></p><p><strong>%s</strong></p>
%s
<h2>Per arm</h2><div class="wrap"><table><tr><th>Arm</th><th>Trials</th><th>Correct</th><th>Total cost</th><th>Cost per successful task</th><th>Mean cost per trial</th></tr>%s</table></div>
<h2>Per task</h2><div class="wrap"><table><tr><th rowspan=2>Task</th><th colspan=3>plain</th><th colspan=3>mogger</th></tr><tr><th>correct</th><th>mean cost</th><th>turns</th><th>correct</th><th>mean cost</th><th>turns</th></tr>%s</table></div>
<h2>Full text</h2><pre>%s</pre>
<h2>Method and caveats</h2><ul>%s</ul>
</body></html>
""" % (e(res.get("ts", "")), e(an["verdict"]["cost"]), e(an["verdict"]["success"]),
       ("<h2 class=warn>Warnings</h2><ul class=warn>%s</ul>" % warn) if warn else "", "".join(arm_rows), "".join(rows), pre, notes)


def write_outputs(res, d):
    common.write_json(os.path.join(d, "last-ab.json"), res)
    with open(os.path.join(d, "report.md"), "w") as f:
        f.write(md_report(res))
    with open(os.path.join(d, "report.html"), "w") as f:
        f.write(html_report(res))


def build_result(trials, meta, seed, partial, n_boot=None):
    an = analyze(trials, seed, n_boot or int(os.environ.get("MOGGER_AB_BOOT", BOOT_N)), partial)
    hooks = hook_summary(trials)
    res = dict(meta)
    res.update({"kind": "ab", "trials": trials, "analysis": an, "hooks": hooks, "partial": partial,
                "completed": len(trials), "estimate_notice": "Costs are the CLI's client-side estimate (total_cost_usd), not a bill.",
                "warnings": warnings_for(trials, an, hooks, partial)})
    res["spent_usd"] = round(sum(float(t.get("cost_usd") or 0.0) for t in trials), 5)
    return res


# ------------------------------------------------------------------ validate (free)
def cmd_validate(a, out):
    problems = []
    tasks = load_tasks()
    ab = ab_dir()
    seen = set()
    if len(tasks) < 6:
        problems.append("need at least 6 tasks, found %d" % len(tasks))
    for t in tasks:
        tid = t.get("id", "?")
        for f in ("id", "title", "fixture", "prompt", "why_hard", "grader", "gold", "bad"):
            if not t.get(f):
                problems.append("%s: missing %s" % (tid, f))
        if tid in seen:
            problems.append("%s: duplicate id" % tid)
        seen.add(tid)
        if "\n" in str(t.get("why_hard", "")):
            problems.append("%s: why_hard must be one line" % tid)
        fx = fixture_dir(t) if t.get("fixture") else ""
        if not fx or not os.path.isdir(fx):
            problems.append("%s: fixture %s missing" % (tid, t.get("fixture")))
            continue
        for bad_name in ("CONSTRAINTS.md", "TASKS.md", "STACK.md", "DECISIONS.md", ".claude"):
            if os.path.exists(os.path.join(fx, bad_name)):
                problems.append("%s: fixture holds %s (mogger state must start empty in both arms)" % (tid, bad_name))
        needs_keys = bool(t.get("gold", {}).get("dir") or t.get("bad", {}).get("dir") or '"hidden"' in json.dumps(t.get("grader")))
        if needs_keys and not os.path.isdir(keys_dir(t)):
            problems.append("%s: no keys folder" % tid)
            continue
        if os.path.abspath(keys_dir(t)).startswith(os.path.abspath(os.path.join(ab, "fixtures"))):
            problems.append("%s: answer keys are inside the fixtures folder" % tid)
        for fn in ("min_lines",):
            ml = t.get(fn)
            if ml:
                n = len(open(os.path.join(fx, ml["file"])).read().split("\n"))
                if n < ml["n"]:
                    problems.append("%s: %s has %d lines, need %d" % (tid, ml["file"], n, ml["n"]))
        for label, want in (("gold", True), ("bad", False), ("blank", False)):
            ws = runner.make_workspace(fx)
            try:
                spec = {"text": ""} if label == "blank" else t[label]
                if spec.get("dir"):
                    apply_tree(ws, read_tree(os.path.join(keys_dir(t), spec["dir"])))
                ctx = {"output": spec.get("text", ""), "workspace": ws, "fixture": fx, "keys_dir": keys_dir(t)}
                (ok, detail), flaky = graders.grade_twice(t["grader"], ctx)
                if ok != want:
                    problems.append("%s: grader says %s for the %s answer (%s)" % (tid, "pass" if ok else "fail", label, detail))
                if flaky:
                    problems.append("%s: grader is not deterministic on the %s answer" % (tid, label))
            finally:
                shutil.rmtree(ws, ignore_errors=True)
    out("ab tasks: %d (%s)" % (len(tasks), ", ".join(t.get("id", "?") for t in tasks)))
    if problems:
        for p in problems:
            out("PROBLEM: " + p)
        return 1
    out("OK: every task passes its gold answer, fails its bad answer and fails a blank answer.")
    return 0


# ------------------------------------------------------------------ commands
def pid_state(d):
    p = os.path.join(d, "running.pid")
    if not os.path.isfile(p):
        return "no"
    try:
        pid = int(open(p).read().strip())
        os.kill(pid, 0)
        return "yes (pid %d)" % pid
    except (ValueError, OSError):
        return "no (stale pid file)"


def model_of(a):
    return a.model or DEFAULT_MODEL


def tasks_of(a):
    ts = load_tasks([x.strip() for x in a.tasks.split(",") if x.strip()] if a.tasks else None)
    if not ts:
        common.die("No A/B tasks found in %s" % os.path.join(ab_dir(), "tasks.json"))
    return ts


def cmd_estimate(a, out):
    tasks, model = tasks_of(a), model_of(a)
    est = build_estimate(tasks, a.repeats, a.jobs, model)
    t = est["table"]
    out("ESTIMATE only. No model calls were made.")
    out("suite: ab (A/B benchmark: plain vs mogger)")
    out("model: %s" % model)
    out("tasks: %d (%s)" % (len(tasks), ", ".join(x["id"] for x in tasks)))
    out("runs: %d (%d tasks x 2 arms x %d repeats)" % (est["runs"], len(tasks), a.repeats))
    for arm in ARMS:
        out("  arm %s: %d runs, about $%.2f" % (arm, est["per_arm"][arm]["runs"], est["per_arm"][arm]["usd"]))
    out("estimated_usd: %.2f (ESTIMATE, pessimistic: token counts x templates/pricing.json, no cache discount, not a bill)" % est["usd"])
    out("minutes: %d (ESTIMATE, %d parallel runs)" % (int(round(est["minutes"])), a.jobs))
    out("trial_cap_usd: %.2f (passed to each trial as --max-budget-usd)" % est["trial_cap_usd"])
    out("assumptions per trial (one table, AB_EST in scripts/eval/ab.py): %d input tokens (+%d for the mogger arm), %d output tokens, %d seconds." % (
        t["in_tokens"], t["arm_b_extra_in_tokens"], t["out_tokens"], t["secs"]))
    out("This would run %d headless Claude sessions for about $%.2f and %d minutes." % (est["runs"], est["usd"], int(round(est["minutes"]))))
    return 0


def cmd_plan(a, out):
    tasks = tasks_of(a)
    plan = build_plan(tasks, a.repeats, a.seed)
    for ln in HEADER:
        out(ln)
    out("")
    out("seed: %s" % a.seed)
    out("plan_digest: %s" % plan_digest(plan))
    out("trials: %d (no model calls were made)" % len(plan))
    i = 0
    while i < len(plan):
        p, q = plan[i], plan[i + 1] if i + 1 < len(plan) else None
        out("repeat %d  %s  first: %s then %s" % (p["repeat"], p["task"]["id"], p["arm"], q["arm"] if q else "-"))
        i += 2
    return 0


def cmd_status(a, out):
    d = ab_state()
    out("running: %s" % pid_state(d))
    prog = common.read_json(os.path.join(d, "progress.json"), None)
    if prog:
        out("progress: %d of %d trials, spent $%.2f of $%.2f (%s)" % (prog.get("done", 0), prog.get("total", 0), prog.get("spent_usd", 0),
                                                                    prog.get("budget_usd", 0), prog.get("state", "?")))
    else:
        out("progress: no run yet")
    last = common.read_json(os.path.join(d, "last-ab.json"), None)
    if last:
        out("last result: %s%s" % (last.get("ts", "?"), ", PARTIAL" if last.get("partial") else ""))
        out(last["analysis"]["verdict"]["cost"])
    return 0


def cmd_report(a, out):
    d = ab_state()
    if a.input:
        raw = common.read_json(a.input, None)
        if raw is None:
            common.die("Cannot read %s" % a.input)
        trials = raw["trials"] if isinstance(raw, dict) else raw
        meta = {"ts": common.now_iso(), "model": (raw.get("model") if isinstance(raw, dict) else None) or "unknown", "effort": "",
                "repeats": None, "seed": a.seed, "jobs": None, "planned": len(trials), "budget_usd": 0.0,
                "cli_version": "", "plugin_version": plugin_version(), "overhead": overhead_facts()}
        res = build_result(trials, meta, a.seed, bool(isinstance(raw, dict) and raw.get("partial")))
        write_outputs(res, d)
    else:
        res = common.read_json(os.path.join(d, "last-ab.json"), None)
        if not res:
            out("No A/B results yet. Run  mogger-eval.sh ab estimate  and then  mogger-eval.sh ab run.")
            return 0
    out("\n".join(text_lines(res)))
    out("")
    out("Files: %s, %s, %s" % (os.path.join(d, "report.md"), os.path.join(d, "report.html"), os.path.join(d, "last-ab.json")))
    return 0


def resolve_budget(a, consent_reader):
    if a.budget is not None:
        try:
            v = float(a.budget)
        except ValueError:
            common.die("--budget needs a number of US dollars, for example --budget 15")
        if not (v > 0) or v != v or v == float("inf"):
            common.die("--budget must be more than 0")
        return v
    c = consent_reader()
    if c:
        return float(c["budget_usd"])
    common.die("Refusing to run: there is no consent and no --budget.\n"
               "The A/B benchmark calls the model and costs money. Run  mogger-eval.sh ab estimate  first.\n"
               "Then either  mogger-eval.sh consent --budget USD  or pass --budget USD to ab run.")


def cmd_run(a, out, consent_reader):
    budget = resolve_budget(a, consent_reader)
    tasks, model = tasks_of(a), model_of(a)
    est = build_estimate(tasks, a.repeats, a.jobs, model)
    cap_trial = float(a.trial_cap) if a.trial_cap else est["trial_cap_usd"]
    for ln in HEADER:
        out(ln)
    out("")
    out("Plan: %d runs, estimated $%.2f (ESTIMATE), hard cap $%.2f, per-trial cap $%.2f, model %s, %d jobs." % (
        est["runs"], est["usd"], budget, cap_trial, model, a.jobs))
    if est["usd"] > budget:
        out("The estimate is above the cap. The run will stop at the cap and report PARTIAL results.")
    plan = build_plan(tasks, a.repeats, a.seed)
    out("seed %s, plan_digest %s" % (a.seed, plan_digest(plan)))
    d = ab_state()
    run_id = time.strftime("%Y%m%d%H%M%S", time.gmtime())
    run_dir = os.path.join(d, "runs", run_id)
    os.makedirs(run_dir, exist_ok=True)
    cli_version = ""
    try:
        r = subprocess.run([common.claude_bin(), "--version"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=20)
        cli_version = r.stdout.decode("utf-8", "replace").strip().split("\n")[0][:80]
    except Exception:
        pass
    plugin_dir = make_plugin_copy(common.plugin_root())
    cap = Cap(budget)
    started = common.now_iso()
    jf = os.path.join(d, "trials.jsonl")
    open(jf, "w").close()

    def fn(item, bl):
        return run_trial(item["task"], item["arm"], item["repeat"], model, a.effort, plugin_dir, run_dir, cap_trial, bl, cli_version)

    def on_done(recs, skipped):
        with open(jf, "a") as f:
            f.write(json.dumps(recs[-1], sort_keys=True) + "\n")
        common.write_json(os.path.join(d, "progress.json"), {"run_id": run_id, "total": len(plan), "done": len(recs), "skipped": skipped,
                                                            "spent_usd": round(cap.spent, 5), "budget_usd": budget, "started": started,
                                                            "updated": common.now_iso(), "state": "running"})
    try:
        recs, skipped = execute(plan, cap, a.jobs, fn, model, out, on_done)
    finally:
        shutil.rmtree(plugin_dir, ignore_errors=True)
    recs.sort(key=lambda r: (r["repeat"], r["task"], r["arm"]))
    partial = skipped > 0
    meta = {"ts": common.now_iso(), "run_id": run_id, "model": model, "effort": a.effort or "default", "repeats": a.repeats,
            "seed": a.seed, "jobs": a.jobs, "planned": len(plan), "skipped": skipped, "budget_usd": budget, "trial_cap_usd": cap_trial,
            "cli_version": cli_version, "plugin_version": plugin_version(), "fingerprint": common.fingerprint(),
            "setting_sources": setting_sources(), "permission_mode": "acceptEdits", "plan_digest": plan_digest(plan),
            "overhead": overhead_facts(), "transcripts_dir": os.path.join("runs", run_id), "tasks": [t["id"] for t in tasks],
            "estimate": {"usd": round(est["usd"], 4), "runs": est["runs"]}}
    res = build_result(recs, meta, a.seed, partial)
    write_outputs(res, d)
    common.write_json(os.path.join(d, "progress.json"), {"run_id": run_id, "total": len(plan), "done": len(recs), "skipped": skipped,
                                                        "spent_usd": res["spent_usd"], "budget_usd": budget, "started": started,
                                                        "updated": common.now_iso(), "state": "finished (PARTIAL)" if partial else "finished"})
    out("")
    out("\n".join(text_lines(res)))
    out("")
    out("Saved: %s" % os.path.join(d, "last-ab.json"))
    out("Report: %s and %s" % (os.path.join(d, "report.md"), os.path.join(d, "report.html")))
    return 0


def main(a, out, consent_reader):
    sub = a.ab_cmd
    if sub is None:
        common.die("Usage: mogger-eval.sh ab estimate|run|plan|status|report|validate")
    if sub == "validate":
        return cmd_validate(a, out)
    if sub == "status":
        return cmd_status(a, out)
    if sub == "report":
        return cmd_report(a, out)
    if sub == "estimate":
        return cmd_estimate(a, out)
    if sub == "plan":
        return cmd_plan(a, out)
    return cmd_run(a, out, consent_reader)
