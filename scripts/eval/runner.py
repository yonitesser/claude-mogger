"""Headless runner: one trial = one `claude -p` call in a fresh temp workspace.

What this relies on (checked against the docs, see mogger-eval.sh header):
  claude -p PROMPT --output-format stream-json --verbose    (docs: headless, cli-reference)
  --model, --effort, --agents '<json>', --agent NAME, --tools, --allowedTools,
  --permission-mode dontAsk, --max-turns, --max-budget-usd, --plugin-dir,
  --no-session-persistence, --settings.
  The stream's last line is a {"type":"result"} event with is_error, subtype
  (success | error_max_turns | error_during_execution | error_max_budget_usd),
  result (final text), num_turns, stop_reason, total_cost_usd (a client-side
  estimate), usage, modelUsage (docs: agent-sdk/typescript, agent-sdk/cost-tracking).
  Assistant events carry message.content[] blocks; a tool call is a block with
  type "tool_use", name, input. A skill invocation is name == "Skill" with
  input.skill (tool list of Claude Code itself; the docs also say "Agent or Skill
  tool call" for parent_tool_use_id). The exact skill-name spelling
  ("mogger:mogger-explain" vs "mogger-explain") is NOT documented, so both are
  accepted by matching the part after the last ":".

Article rule 7 ("leftover state must not leak"): every trial gets a brand new temp
copy of the fixture with a one-commit git history, deleted afterwards. Answer keys
are never copied into it.
Article rule 6 (plumbing): timeouts, API errors, cut-off answers and empty output are
classified here and counted separately from wrong answers.
"""
import json
import os
import re
import shutil
import signal
import subprocess
import tempfile
import threading
import time

import common
import graders

PLUMBING = ("timeout", "api_error", "truncated", "empty", "no_result")


def strip_savings_section(body):
    """The agents end with an optional 'log the savings estimate' section that runs a
    plugin script. In an eval it is pure noise (and needs CLAUDE_PLUGIN_ROOT), so it
    is cut from the prompt that is tested. Later '## ' sections are kept."""
    out, skip = [], False
    for ln in body.split("\n"):
        if ln.startswith("## "):
            skip = ln.startswith("## Before you finish: log the savings")
        if not skip:
            out.append(ln)
    return "\n".join(out).strip() + "\n"


# ------------------------------------------------------------ workspace (rule 7)
def make_workspace(fixture_dir):
    ws = tempfile.mkdtemp(prefix="mogger-eval-ws-")
    for name in os.listdir(fixture_dir):
        src = os.path.join(fixture_dir, name)
        dst = os.path.join(ws, name)
        if os.path.isdir(src):
            shutil.copytree(src, dst, ignore=shutil.ignore_patterns("__pycache__", ".git"))
        else:
            shutil.copy2(src, dst)
    if shutil.which("git"):
        env = dict(os.environ, GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_SYSTEM=os.devnull)
        try:
            subprocess.run(["git", "init", "-q"], cwd=ws, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
            subprocess.run(["git", "add", "-A"], cwd=ws, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
            subprocess.run(["git", "-c", "user.name=eval", "-c", "user.email=eval@example.invalid", "-c", "commit.gpgsign=false",
                            "commit", "-q", "-m", "fixture import"], cwd=ws, env=env, stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, timeout=30)
        except Exception:
            pass
    return ws


def make_plugin_copy(root, description_overrides=None):
    """Sanitised plugin copy: plugin.json + skills + agents only. Hooks are left out on
    purpose (they would act on the temp workspace and add noise). Optional per-skill
    description overrides are how the hillclimber tests a candidate."""
    dst = tempfile.mkdtemp(prefix="mogger-eval-plugin-")
    for d in (".claude-plugin", "skills", "agents"):
        s = os.path.join(root, d)
        if os.path.isdir(s):
            shutil.copytree(s, os.path.join(dst, d))
    for skill, desc in (description_overrides or {}).items():
        p = os.path.join(dst, "skills", skill, "SKILL.md")
        if os.path.isfile(p):
            new = replace_description(open(p).read(), desc)
            with open(p, "w") as f:
                f.write(new)
    return dst


def replace_description(text, desc):
    desc = " ".join(desc.split())
    lines = text.split("\n")
    seen_open = False
    for i, ln in enumerate(lines):
        if ln.strip() == "---":
            if seen_open:
                break
            seen_open = True
            continue
        if seen_open and ln.startswith("description:"):
            lines[i] = "description: " + desc
            break
    return "\n".join(lines)


# ------------------------------------------------------------ process
def _kill(p):
    try:
        os.killpg(p.pid, signal.SIGKILL)
    except Exception:
        try:
            p.kill()
        except Exception:
            pass


def run_claude(cmd, cwd, env, timeout, stop=None):
    """Returns (lines, returncode, timed_out, stopped_early, stderr_text)."""
    errf = tempfile.TemporaryFile()
    try:
        p = subprocess.Popen(cmd, cwd=cwd, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                             stderr=errf, start_new_session=True)
    except OSError as e:
        return [], 127, False, False, "cannot start %s: %s" % (cmd[0], e)
    lines = []
    state = {"stopped": False}

    def reader():
        try:
            for raw in p.stdout:
                line = raw.decode("utf-8", "replace")
                lines.append(line)
                if stop is not None and stop(line):
                    state["stopped"] = True
                    _kill(p)
                    break
        except Exception:
            pass

    t = threading.Thread(target=reader, daemon=True)
    t.start()
    deadline = time.time() + timeout
    timed_out = False
    while t.is_alive():
        t.join(0.05)
        if time.time() > deadline:
            timed_out = True
            _kill(p)
            break
    t.join(3)
    try:
        p.wait(timeout=5)
    except Exception:
        _kill(p)
    try:
        errf.seek(0)
        err = errf.read().decode("utf-8", "replace")[-2000:]
    finally:
        errf.close()
    return lines, (p.returncode if p.returncode is not None else -9), timed_out, state["stopped"], err


# ------------------------------------------------------------ stream parsing
def parse_stream(lines):
    info = {"text": "", "result": None, "tool_uses": [], "skills": [], "api_retries": 0,
            "api_error": "", "model": "", "in_tok": 0, "out_tok": 0}
    last_assistant_text = ""
    seen_msg = set()
    for raw in lines:
        raw = raw.strip()
        if not raw or raw[0] != "{":
            continue
        try:
            ev = json.loads(raw)
        except Exception:
            continue
        t = ev.get("type")
        if t == "system":
            if ev.get("subtype") == "init" and ev.get("model"):
                info["model"] = ev.get("model")
            if ev.get("subtype") == "api_retry":
                info["api_retries"] += 1
                info["api_error"] = str(ev.get("error") or ev.get("error_status") or "api_retry")
        elif t == "assistant":
            msg = ev.get("message") or {}
            mid = msg.get("id")
            u = msg.get("usage") or {}
            if mid is None or mid not in seen_msg:
                if mid is not None:
                    seen_msg.add(mid)
                info["in_tok"] += int(u.get("input_tokens") or 0) + int(u.get("cache_creation_input_tokens") or 0)
                info["out_tok"] += int(u.get("output_tokens") or 0)
            texts = []
            for b in msg.get("content") or []:
                if not isinstance(b, dict):
                    continue
                if b.get("type") == "text":
                    texts.append(b.get("text", ""))
                elif b.get("type") == "tool_use":
                    info["tool_uses"].append(b.get("name", ""))
                    if b.get("name") == "Skill":
                        inp = b.get("input") or {}
                        name = inp.get("skill") or inp.get("name") or inp.get("command") or ""
                        info["skills"].append(str(name).split(":")[-1].strip())
            if texts:
                last_assistant_text = "\n".join(texts)
        elif t == "result":
            info["result"] = ev
    r = info["result"]
    if r is not None and isinstance(r.get("result"), str):
        info["text"] = r["result"]
    else:
        info["text"] = last_assistant_text
    return info


def classify(info, timed_out, rc, stderr, want_text=True):
    """Plumbing classification. Returns (status, note). status 'ok' means the model
    produced something gradable; it says nothing about correctness."""
    if timed_out:
        return "timeout", "no answer within the time limit"
    r = info["result"]
    if r is None:
        note = (stderr or "").strip().splitlines()[-1:] or ["no result event in the stream"]
        return ("api_error" if (info["api_retries"] or rc not in (0,)) else "no_result"), note[0][:200]
    st = r.get("subtype") or ""
    if st in ("error_max_turns", "error_max_budget_usd") or r.get("stop_reason") == "max_tokens":
        return "truncated", st or "max_tokens"
    if r.get("is_error") or st.startswith("error"):
        return "api_error", (str(r.get("result") or st))[:200]
    if want_text and not info["text"].strip():
        return "empty", "empty answer"
    return "ok", ""


def cost_of(info, tier, stopped_early=False):
    r = info["result"]
    if r is not None and isinstance(r.get("total_cost_usd"), (int, float)):
        return float(r["total_cost_usd"]), "reported"
    return common.token_cost(tier, info["in_tok"], info["out_tok"]), "estimate"


# ------------------------------------------------------------ trials
def _child_env(task_id, trial_no, extra=None):
    env = dict(os.environ)
    env["MOGGER_EVAL_TASK_ID"] = task_id
    env["MOGGER_EVAL_TRIAL"] = str(trial_no)
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    if extra:
        env.update(extra)
    return env


def _extra_args():
    """--setting-sources project keeps the user's own hooks (including mogger's session
    hooks) out of the trials; set MOGGER_EVAL_SETTING_SOURCES= (empty) to load everything,
    for example if auth comes from user settings. MOGGER_EVAL_EXTRA_ARGS adds raw flags."""
    args = []
    src = os.environ.get("MOGGER_EVAL_SETTING_SOURCES", "project")
    if src:
        args += ["--setting-sources", src]
    v = os.environ.get("MOGGER_EVAL_EXTRA_ARGS", "").strip()
    return args + (v.split() if v else [])


def _deny_settings():
    ed = common.evals_dir()
    rules = []
    for tool in ("Read", "Grep", "Glob"):
        rules.append("%s(/%s/**)" % (tool, ed))
    return json.dumps({"permissions": {"deny": rules}})


def _save_transcript(run_dir, name, lines, extra_head):
    if not run_dir:
        return ""
    rel = os.path.join("runs", os.path.basename(run_dir), name + ".jsonl")
    p = os.path.join(run_dir, name + ".jsonl")
    os.makedirs(run_dir, exist_ok=True)
    with open(p, "w") as f:
        f.write(json.dumps({"type": "mogger_eval_meta", **extra_head}) + "\n")
        for ln in lines:
            f.write(ln if ln.endswith("\n") else ln + "\n")
    return os.path.join("runs", os.path.basename(run_dir), name + ".jsonl")


def routing_trial(task, agent, cand, repeat, run_dir, budget_left):
    tier, effort = cand["tier"], cand["effort"]
    fixture = os.path.join(common.evals_dir(), "fixtures", task["fixture"])
    ws = make_workspace(fixture)
    t0 = time.time()
    try:
        body = strip_savings_section(agent["body"])
        adef = {"description": agent["description"], "prompt": body, "model": tier}
        if agent["tools"]:
            adef["tools"] = agent["tools"]
        cap = min(float(os.environ.get("MOGGER_EVAL_TRIAL_CAP_USD", "0.50")), max(budget_left, 0.01))
        cmd = [common.claude_bin(), "-p", task["prompt"], "--output-format", "stream-json", "--verbose",
               "--model", tier, "--agents", json.dumps({agent["name"]: adef}), "--agent", agent["name"],
               "--permission-mode", "dontAsk", "--no-session-persistence",
               "--max-turns", os.environ.get("MOGGER_EVAL_MAX_TURNS", "25"),
               "--max-budget-usd", "%.2f" % cap, "--settings", _deny_settings()]
        if effort != "default":
            cmd += ["--effort", effort]
        if agent["tools"]:
            cmd += ["--tools=" + ",".join(agent["tools"]), "--allowedTools=" + ",".join(agent["tools"])]
        cmd += _extra_args()
        timeout = int(os.environ.get("MOGGER_EVAL_TIMEOUT", "300"))
        lines, rc, timed_out, _, err = run_claude(cmd, ws, _child_env(task["id"], repeat), timeout)
        info = parse_stream(lines)
        status, note = classify(info, timed_out, rc, err)
        cost, csrc = cost_of(info, tier)
        rec = {"kind": "routing", "task": task["id"], "agent": agent["name"], "cand": "%s@%s" % (tier, effort),
               "tier": tier, "effort": effort, "repeat": repeat, "status": status, "note": note,
               "passed": None, "detail": "", "grader_flaky": False, "cost_usd": cost, "cost_source": csrc,
               "seconds": round(time.time() - t0, 1), "chars": len(info["text"])}
        if status == "ok":
            ctx = {"output": info["text"], "workspace": ws, "fixture": fixture}
            (ok, detail), flaky = graders.grade_twice(task["grader"], ctx)
            rec.update(passed=bool(ok), detail=detail, grader_flaky=flaky)
        rec["transcript"] = _save_transcript(run_dir, "%s__%s__%d" % (task["id"], rec["cand"], repeat), lines,
                                             {"task": task["id"], "cand": rec["cand"], "repeat": repeat, "status": status})
        return rec
    finally:
        shutil.rmtree(ws, ignore_errors=True)


def trigger_trial(item, plugin_dir, model, repeat, run_dir, budget_left):
    """item: {id, skill, should(bool), prompt}. Observable: a Skill tool_use in the stream."""
    fixture = os.path.join(common.evals_dir(), "fixtures", "shop")
    ws = make_workspace(fixture)
    t0 = time.time()
    try:
        cap = min(float(os.environ.get("MOGGER_EVAL_TRIGGER_CAP_USD", "0.15")), max(budget_left, 0.01))
        cmd = [common.claude_bin(), "-p", item["prompt"], "--output-format", "stream-json", "--verbose",
               "--model", model, "--plugin-dir", plugin_dir, "--permission-mode", "dontAsk",
               "--allowedTools=Skill", "--no-session-persistence",
               "--max-turns", os.environ.get("MOGGER_EVAL_TRIGGER_MAX_TURNS", "3"),
               "--max-budget-usd", "%.2f" % cap] + _extra_args()

        def stop(line):  # the answer to "was it invoked" is known at the first Skill call
            return '"Skill"' in line and '"tool_use"' in line and bool(parse_stream([line])["skills"])

        timeout = int(os.environ.get("MOGGER_EVAL_TRIGGER_TIMEOUT", "120"))
        lines, rc, timed_out, stopped, err = run_claude(cmd, ws, _child_env(item["id"], repeat), timeout, stop)
        info = parse_stream(lines)
        if info["skills"]:
            status, note = "ok", ""
        else:
            status, note = classify(info, timed_out, rc, err, want_text=False)
            if status in ("truncated", "empty"):
                status, note = "ok", ""   # ran out of turns without a Skill call: it did not trigger
        tier = common.tier_of(model)
        cost, csrc = cost_of(info, tier, stopped)
        invoked = sorted(set(info["skills"]))
        rec = {"kind": "triggers", "task": item["id"], "skill": item["skill"], "should": item["should"], "cand": tier,
               "tier": tier, "repeat": repeat, "status": status, "note": note, "invoked": invoked,
               "triggered": item["skill"] in invoked, "cost_usd": cost, "cost_source": csrc,
               "seconds": round(time.time() - t0, 1)}
        rec["passed"] = (rec["triggered"] == item["should"]) if status == "ok" else None
        rec["transcript"] = _save_transcript(run_dir, "%s__%d" % (item["id"], repeat), lines,
                                             {"task": item["id"], "repeat": repeat, "status": status})
        return rec
    finally:
        shutil.rmtree(ws, ignore_errors=True)
