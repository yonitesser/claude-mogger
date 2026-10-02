#!/usr/bin/env bash
# Tests for the A/B benchmark: scripts/mogger-eval.sh ab ...   Run: bash tests/evals-ab.test.sh
# No API, no network: a stub `claude` (bash) writes canned stream-json. Every call to the stub is
# logged, so "estimate/plan/report made no model call" is checked, not assumed.
# Self-contained temp sandbox; bash 3.2 / BSD userland safe.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EV="$ROOT/scripts/mogger-eval.sh"
PASS=0; FAIL=0
SB=$(mktemp -d)
: "${SB:?}"
trap 'rm -rf "$SB"' EXIT
export PYTHONDONTWRITEBYTECODE=1

ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
has()   { case "$OUT" in *"$2"*) ok "$1";; *) bad "$1"; printf '       missing: [%s]\n       in: %s\n' "$2" "$(printf '%s' "$OUT" | head -c 700)";; esac; }
hasnt() { case "$OUT" in *"$2"*) bad "$1"; printf '       unexpected: [%s]\n' "$2";; *) ok "$1";; esac; }
eq()    { [ "$2" = "$3" ] && ok "$1" || { bad "$1"; printf '       want [%s] got [%s]\n' "$3" "$2"; }; }
w() { mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" > "$1"; }

# ---------------------------------------------------------------- sandbox
PLUG="$SB/plugin"; PROJ="$SB/proj"; STUB="$SB/stub"; BIN="$SB/bin"; EVD="$SB/evals"
mkdir -p "$PROJ" "$STUB" "$BIN"
export STUB_DIR="$STUB"
export MOGGER_CLAUDE_BIN="$BIN/claude"
export MOGGER_EVAL_PLUGIN_ROOT="$PLUG"
export MOGGER_EVAL_DIR="$EVD"
unset MOGGER_EVAL_STATE_DIR MOGGER_EVAL_PRICING MOGGER_AB_EST_IN MOGGER_AB_EST_OUT MOGGER_AB_EST_SECS MOGGER_AB_EST_EXTRA_IN MOGGER_AB_TRIAL_CAP_MIN MOGGER_AB_TIMEOUT MOGGER_AB_BOOT MOGGER_EVAL_SETTING_SOURCES MOGGER_EVAL_EXTRA_ARGS

w "$PLUG/.claude-plugin/plugin.json" '{"name":"mogger","version":"0.0.0"}'
w "$PLUG/templates/pricing.json" '{"models":{"haiku":{"input_per_mtok":1.00,"output_per_mtok":5.00},"sonnet":{"input_per_mtok":2.00,"output_per_mtok":10.00},"opus":{"input_per_mtok":4.00,"output_per_mtok":20.00}}}'
w "$PLUG/hooks/hooks.json" '{"hooks":{}}'
w "$PLUG/skills/alpha/SKILL.md" "$(printf '%s\n' '---' 'name: alpha' 'description: Alpha thing.' '---' '' 'Body.')"
w "$PLUG/evals/SECRET-KEY.txt" 'answer key that must never reach arm B'
w "$PLUG/tests/t.sh" 'echo test'

# test A/B tasks: six tiny ones, graded by text
mk_ab() {  # mk_ab <evals-dir>
  w "$1/ab/fixtures/mini/a.txt" 'nothing to see here'
  local n out=""
  for n in alpha beta gamma delta eps zeta; do
    out="$out"'{"id":"ab-'"$n"'","title":"task '"$n"'","neutral":true,"fixture":"mini","prompt":"Do the '"$n"' thing and say done-'"$n"'.","why_hard":"A decoy line next to the real one makes the first match wrong.","max_turns":9,"grader":{"type":"contains_all","values":["done-'"$n"'"]},"gold":{"text":"done-'"$n"'"},"bad":{"text":"nope"}},'
  done
  out="${out%,}"
  w "$1/ab/tasks.json" '{"version":1,"tasks":['"$out"']}'
}
mk_ab "$EVD"
TASKS_SUM_BEFORE=$(cksum < "$EVD/ab/tasks.json")

# ---------------------------------------------------------------- the stub claude
cat > "$BIN/claude" <<'EOF_STUB'
#!/usr/bin/env bash
S="$STUB_DIR"
echo "$*" >> "$S/all.log"
case "${1:-}" in --version) echo "9.9.9 (Claude Code stub)"; exit 0 ;; esac
id="${MOGGER_EVAL_TASK_ID:-none}"; rep="${MOGGER_EVAL_TRIAL:-1}"
arm=plain; plugin=""; prev=""
for a in "$@"; do
  [ "$prev" = "--plugin-dir" ] && { arm=mogger; plugin="$a"; }
  prev="$a"
done
mkdir -p "$S/calls"
K="$S/calls/$id.$rep.$arm"
{ printf '%s\n' "$id" "$rep" "$arm"; printf '%s\n' "$@"; } > "$K.args"
echo "$PWD" > "$K.cwd"
if [ -e trial.marker ]; then echo dirty > "$K.fresh"; else echo clean > "$K.fresh"; fi
{ ls -A | sort | tr '\n' ' '; echo; } > "$K.ls"
: > trial.marker
git log --oneline 2>/dev/null | wc -l | tr -d ' ' > "$K.git"
env | grep -E '^CLAUDE_CODE_DISABLE_(AUTO_MEMORY|CLAUDE_MDS)=' | sort > "$K.env"
if [ -n "$plugin" ]; then
  { [ -f "$plugin/.claude-plugin/plugin.json" ] && echo plugin-ok || echo plugin-missing
    [ -d "$plugin/evals" ] && echo has-evals || echo no-evals
    [ -d "$plugin/hooks" ] && echo has-hooks; } > "$K.plugin"
fi
echo "$id.$rep.$arm" >> "$S/order.log"
[ -f "$S/delay" ] && sleep "$(cat "$S/delay")"
mode=normal; [ -f "$S/mode.$id.$arm" ] && mode=$(cat "$S/mode.$id.$arm")
[ "$mode" = timeout ] && { sleep 30; exit 0; }
cost=0.10
[ -f "$S/cost" ] && cost=$(cat "$S/cost")
[ -f "$S/cost.$arm" ] && cost=$(cat "$S/cost.$arm")
[ -f "$S/cost.$id.$arm" ] && cost=$(cat "$S/cost.$id.$arm")
text="done-${id#ab-}"
[ -f "$S/ans.$id.$arm" ] && text=$(cat "$S/ans.$id.$arm")
[ -f "$S/ans.$id" ] && [ ! -f "$S/ans.$id.$arm" ] && text=$(cat "$S/ans.$id")
leak=0; [ -f "$S/leak" ] && leak=1
nohooks=0; [ -f "$S/nohooks" ] && nohooks=1
exec python3 "$(dirname "$0")/emit.py" "$arm" "$mode" "$cost" "$text" "$leak" "$nohooks"
EOF_STUB
cat > "$BIN/emit.py" <<'EOF_EMIT'
import json, sys
arm, mode, cost, text, leak, nohooks = sys.argv[1:7]
init = {"type": "system", "subtype": "init", "model": "stub-sonnet", "claude_code_version": "9.9.9",
        "plugins": ([{"name": "mogger", "path": "/x"}] if arm == "mogger" else [])}
print(json.dumps(init))
hooks = []
if (arm == "mogger" and nohooks != "1") or leak == "1":
    hooks = [("h1", "PreToolUse", "PreToolUse:Bash", "bash /p/hooks/scripts/secret-guard-bash.sh"),
             ("h2", "SessionStart", "SessionStart:startup", "bash /p/hooks/scripts/session-start.sh"),
             ("h3", "Stop", "Stop:done", "")]
for hid, ev, name, cmd in hooks:
    print(json.dumps({"type": "system", "subtype": "hook_started", "hook_id": hid, "hook_event": ev, "hook_name": name, "command": cmd}))
    print(json.dumps({"type": "system", "subtype": "hook_response", "hook_id": hid, "hook_event": ev, "hook_name": name, "outcome": "success", "exit_code": 0}))
print(json.dumps({"type": "assistant", "message": {"id": "m1", "content": [{"type": "text", "text": "working"}], "usage": {"input_tokens": 10, "output_tokens": 5}}}))
sub, iserr = "success", False
if mode == "apierror":
    sub, iserr, text = "error_during_execution", True, ""
if mode == "truncated":
    sub = "error_max_turns"
print(json.dumps({"type": "result", "subtype": sub, "is_error": iserr, "result": text, "num_turns": 7 if arm == "mogger" else 5,
                  "duration_ms": 4200, "stop_reason": "end_turn", "total_cost_usd": float(cost),
                  "usage": {"input_tokens": 1000, "output_tokens": 200, "cache_read_input_tokens": 5000, "cache_creation_input_tokens": 300}}))
EOF_EMIT
chmod +x "$BIN/claude"
resetstub() { rm -rf "$STUB"; mkdir -p "$STUB"; }
abx() {  # abx <args...>: run `ab ...` inside the project sandbox
  OUT=$(cd "$PROJ" && bash "$EV" ab "$@" 2>&1); RC=$?
}
reset_project() { rm -rf "$PROJ/.claude"; }
pj() {  # pj <file> <python expr on d>
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$1" "$2"
}
ABS="$PROJ/.claude/state/evals/ab"
LASTAB="$ABS/last-ab.json"
argfile() { printf '%s/calls/%s.%s.%s.args' "$STUB" "$1" "$2" "$3"; }   # argfile <id> <rep> <arm>
nfiles() { find "$1" -maxdepth 1 -type f -name "$2" 2>/dev/null | wc -l | tr -d ' '; }
no_calls() {  # no_calls <label>
  [ ! -f "$STUB/all.log" ] && ok "$1: the stub claude was never called" || bad "$1: the stub claude was never called"
}

# ================================================================ portability lint
echo "== portability lint"
for f in "$ROOT/scripts/mogger-eval.sh" "$ROOT/tests/evals-ab.test.sh"; do
  body=$(grep -v '^[[:space:]]*#' "$f")
  hits=$(printf '%s\n' "$body" | grep -E 'mapfile|readarray|declare -A|grep -P|sed -i|head -n 0|readlink -f|date -d|stat -c|[$][{][a-z_]+,,|[[]A-Z[]]|[[]a-z[]]' | grep -v 'hits=' | head -1)
  [ -z "$hits" ] && ok "no bash4/GNU-only constructs: $(basename "$f")" || { bad "portability: $(basename "$f")"; printf '       %s\n' "$hits"; }
  bash -n "$f" 2>/dev/null && ok "bash -n $(basename "$f")" || bad "bash -n $(basename "$f")"
done
for f in "$ROOT"/scripts/eval/*.py; do python3 -m py_compile "$f" 2>/dev/null && ok "py_compile $(basename "$f")" || bad "py_compile $(basename "$f")"; done
find "$ROOT/scripts/eval" -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null
bad_http=$(grep -c 'python3 -m http' "$ROOT/scripts/eval/ab.py")
eq "ab.py starts no http server" "$bad_http" "0"

# ================================================================ shipped data
echo "== shipped tasks are valid (real evals/ab)"
OUT=$(cd "$PROJ" && MOGGER_EVAL_PLUGIN_ROOT="$ROOT" MOGGER_EVAL_DIR="$ROOT/evals" bash "$EV" ab validate 2>&1); RC=$?
eq "validate exits 0 on the real tasks" "$RC" "0"
has "validate: gold passes, bad and blank fail" "OK: every task passes its gold answer, fails its bad answer and fails a blank answer."
has "validate: lists six tasks" "ab tasks: 6"
REALAB="$ROOT/evals/ab"
ntask=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["tasks"]))' "$REALAB/tasks.json")
[ "$ntask" -ge 6 ] && ok "at least 6 tasks ($ntask)" || bad "at least 6 tasks ($ntask)"
why=$(python3 -c 'import json,sys; print(sum(1 for t in json.load(open(sys.argv[1]))["tasks"] if len(t.get("why_hard",""))<40 or "\n" in t["why_hard"]))' "$REALAB/tasks.json")
eq "every task has a one-line why_hard of substance" "$why" "0"
nogb=$(python3 -c 'import json,sys; print(sum(1 for t in json.load(open(sys.argv[1]))["tasks"] if not (t.get("gold") and t.get("bad") and t.get("grader"))))' "$REALAB/tasks.json")
eq "every task has a gold answer, a bad answer and a grader" "$nogb" "0"
neutral=$(python3 -c 'import json,sys; print(",".join(str(int(bool(t["neutral"]))) for t in json.load(open(sys.argv[1]))["tasks"]))' "$REALAB/tasks.json")
eq "tasks 1-2 are marked neutral, 3-6 mogger-feature" "$neutral" "1,1,0,0,0,0"
leak=$(grep -rl -E '"(gold|why_hard|grader|hidden)"' "$REALAB/fixtures" 2>/dev/null | head -1)
eq "no answer keys inside fixtures" "$leak" ""
state_files=$(find "$REALAB/fixtures" \( -name CONSTRAINTS.md -o -name TASKS.md -o -name STACK.md -o -name DECISIONS.md -o -name .claude \) 2>/dev/null | wc -l | tr -d ' ')
eq "fixtures hold no mogger state files" "$state_files" "0"
plines=$(wc -l < "$REALAB/fixtures/catalog/config/plans.py" | tr -d ' ')
[ "$plines" -ge 500 ] && ok "big-file fixture has 500+ lines ($plines)" || bad "big-file fixture has 500+ lines ($plines)"
[ -f "$REALAB/fixtures/reports/registry.txt" ] && ok "dependency fixture ships a registry file list" || bad "dependency fixture ships a registry file list"
no_calls "validate"

echo "== validate catches broken tasks"
VAR="$SB/ev_broken"; mk_ab "$VAR"
python3 - "$VAR/ab/tasks.json" <<'EOF_PYB'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["tasks"][0]["bad"] = {"text": "done-alpha"}            # a bad answer that passes
d["tasks"][1]["grader"] = {"type": "contains_none", "values": ["zzz"]}  # a grader that passes a blank
del d["tasks"][2]["why_hard"]
json.dump(d, open(p, "w"))
EOF_PYB
OUT=$(cd "$PROJ" && MOGGER_EVAL_DIR="$VAR" bash "$EV" ab validate 2>&1); RC=$?
eq "validate exits 1 on broken tasks" "$RC" "1"
has "validate: bad answer that passes is reported" "ab-alpha: grader says pass for the bad answer"
has "validate: grader that passes blank is reported" "ab-beta: grader says pass for the blank answer"
has "validate: missing why_hard is reported" "ab-gamma: missing why_hard"
VAR2="$SB/ev_state"; mk_ab "$VAR2"; w "$VAR2/ab/fixtures/mini/CONSTRAINTS.md" 'stale rule'
OUT=$(cd "$PROJ" && MOGGER_EVAL_DIR="$VAR2" bash "$EV" ab validate 2>&1); RC=$?
has "validate: stale mogger state in a fixture is reported" "mogger state must start empty"
VAR3="$SB/ev_few"; mk_ab "$VAR3"
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["tasks"]=d["tasks"][:3]; json.dump(d, open(p,"w"))' "$VAR3/ab/tasks.json"
OUT=$(cd "$PROJ" && MOGGER_EVAL_DIR="$VAR3" bash "$EV" ab validate 2>&1); RC=$?
has "validate: fewer than 6 tasks is reported" "need at least 6 tasks"

# ================================================================ estimate (no model calls)
echo "== estimate (no model calls)"
resetstub; reset_project
abx estimate
eq "estimate exits 0" "$RC" "0"
has "estimate says no model calls were made" "No model calls were made"
has "estimate: 36 runs by default (6 tasks x 2 arms x 3 repeats)" "runs: 36 (6 tasks x 2 arms x 3 repeats)"
has "estimate: plain arm 18 runs, 150k in + 8k out on sonnet = 0.38 each" "arm plain: 18 runs, about \$6.84"
has "estimate: mogger arm adds 15k input tokens = 0.41 each" "arm mogger: 18 runs, about \$7.38"
has "estimate: total dollars" "estimated_usd: 14.22"
has "estimate is labelled ESTIMATE and pessimistic" "ESTIMATE, pessimistic"
has "estimate: minutes (36 runs x 120 s / 2 jobs)" "minutes: 36"
has "estimate: default model is the sonnet alias" "model: sonnet"
has "estimate: per-trial cap is max(0.50, 2 x 0.41)" "trial_cap_usd: 0.82"
has "estimate: assumptions come from one table" "AB_EST"
abx estimate --repeats 1 --tasks ab-alpha,ab-beta
has "estimate: --tasks and --repeats shrink it to 4 runs" "runs: 4 (2 tasks x 2 arms x 1 repeats)"
abx estimate --model haiku
has "estimate: --model haiku changes the price (1/5 per Mtok)" "estimated_usd: 7.11"
has "estimate: --model is echoed" "model: haiku"
abx estimate --repeats 5
has "estimate: --repeats 5 gives 60 runs" "runs: 60"
MOGGER_AB_EST_IN=100000 abx estimate
has "estimate: the token table is tunable by env" "estimated_usd: 10.62"
abx estimate --tasks nonsense
eq "estimate: an unknown task is an error (exit 2)" "$RC" "2"
has "estimate: the unknown-task error names the known tasks" "Known: ab-alpha"
abx estimate --jobs 4
has "estimate: more jobs, fewer minutes" "minutes: 18"
no_calls "estimate"
[ ! -e "$LASTAB" ] && ok "estimate wrote no results" || bad "estimate wrote no results"

# ================================================================ plan, seeded order
echo "== plan: interleave and seeded randomisation"
abx plan
eq "plan exits 0" "$RC" "0"
D1=$(printf '%s\n' "$OUT" | grep '^plan_digest:')
abx plan
D2=$(printf '%s\n' "$OUT" | grep '^plan_digest:')
eq "plan is reproducible with the same seed" "$D2" "$D1"
abx plan --seed other-seed
D3=$(printf '%s\n' "$OUT" | grep '^plan_digest:')
[ "$D3" != "$D1" ] && ok "a different seed gives a different plan" || bad "a different seed gives a different plan"
abx plan --seed other-seed
D4=$(printf '%s\n' "$OUT" | grep '^plan_digest:')
eq "a different seed is itself reproducible" "$D4" "$D3"
abx plan --repeats 2
firsts=$(printf '%s\n' "$OUT" | grep '^repeat ' | sed 's/.*first: \([^ ]*\) then.*/\1/' | sort -u | wc -l | tr -d ' ')
eq "arm order is randomised: both arms go first sometimes" "$firsts" "2"
has "plan lists every trial pair (repeat 2, last task)" "repeat 2  ab-zeta"
has "plan header names the verified flags" "VERIFIED against the docs"
has "plan header names the assumptions" "ASSUMED (not proven against a live API)"
has "plan header says loudly that hooks under acceptEdits are unverified" "Plugin hooks run under --permission-mode acceptEdits"
has "plan header cites the headless docs URL" "https://code.claude.com/docs/en/headless"
has "plan header warns acceptEdits does not sandbox" "acceptEdits does not sandbox"
has "plan header explains why --bare is not used" "--bare is NOT used"
has "plan says no model calls were made" "no model calls were made"
no_calls "plan"

# ================================================================ consent / budget gate
echo "== consent and budget gate"
resetstub; reset_project
abx run --repeats 1
eq "run without consent or --budget refuses (exit 2)" "$RC" "2"
has "refusal says why" "no consent and no --budget"
no_calls "refused run"
abx run --budget abc
[ "$RC" -ne 0 ] && ok "run rejects a non-number budget" || bad "run rejects a non-number budget"
abx run --budget 0
[ "$RC" -ne 0 ] && ok "run rejects a zero budget" || bad "run rejects a zero budget"
abx run --budget -3
[ "$RC" -ne 0 ] && ok "run rejects a negative budget" || bad "run rejects a negative budget"
no_calls "bad-budget runs"
abx run --background --repeats 1
eq "background run without consent refuses synchronously (exit 2)" "$RC" "2"
[ ! -f "$ABS/running.pid" ] && ok "refused background run left no pid file" || bad "refused background run left no pid file"
no_calls "refused background run"
OUT=$(cd "$PROJ" && bash "$EV" consent --budget 25 2>&1); RC=$?
eq "consent --budget 25 is accepted" "$RC" "0"
abx run --repeats 1 --tasks ab-alpha --jobs 1
eq "with consent.json a run is allowed (no --budget needed)" "$RC" "0"
has "run echoes the hard cap from consent" "hard cap \$25.00"
rm -rf "$PROJ/.claude/state/evals/consent.json"

# ================================================================ full run with the stub
echo "== run: both arms, six tasks, two repeats"
resetstub; reset_project
abx run --budget 50 --repeats 2 --jobs 2
eq "run exits 0" "$RC" "0"
[ -f "$LASTAB" ] && ok "last-ab.json written" || bad "last-ab.json written"
[ -f "$ABS/report.md" ] && ok "report.md written" || bad "report.md written"
[ -f "$ABS/report.html" ] && ok "report.html written" || bad "report.html written"
eq "24 trials ran (6 tasks x 2 arms x 2 repeats)" "$(pj "$LASTAB" 'len(d["trials"])')" "24"
eq "the run is not partial" "$(pj "$LASTAB" 'd["partial"]')" "False"
eq "12 trials per arm" "$(pj "$LASTAB" 'sorted(set((a, sum(1 for t in d["trials"] if t["arm"]==a)) for a in ("plain","mogger")))')" "[('mogger', 12), ('plain', 12)]"
eq "the stub saw 24 calls" "$(nfiles "$STUB/calls" '*.args')" "24"
eq "the model name is recorded" "$(pj "$LASTAB" 'd["model"]')" "sonnet"
eq "the default repeats are recorded for this run" "$(pj "$LASTAB" 'd["repeats"]')" "2"
eq "CLI version is recorded (from the init event)" "$(pj "$LASTAB" 'd["trials"][0]["cli_version"]')" "9.9.9"
eq "CLI version is recorded for the run (claude --version)" "$(pj "$LASTAB" 'd["cli_version"]')" "9.9.9 (Claude Code stub)"
eq "plugin version is recorded" "$(pj "$LASTAB" 'd["plugin_version"]')" "0.0.0"
eq "the seed is recorded" "$(pj "$LASTAB" 'd["seed"]')" "mogger-ab-v1"
eq "tasks.json is untouched by a run (no hillclimbing)" "$(cksum < "$EVD/ab/tasks.json")" "$TASKS_SUM_BEFORE"

echo "== arm isolation: same everything except the plugin"
A_PLAIN=$(argfile ab-alpha 1 plain); A_MOG=$(argfile ab-alpha 1 mogger)
[ -f "$A_PLAIN" ] && [ -f "$A_MOG" ] && ok "both arms ran ab-alpha repeat 1" || bad "both arms ran ab-alpha repeat 1"
case "$(cat "$A_PLAIN")" in *"--plugin-dir"*) bad "plain arm has no --plugin-dir";; *) ok "plain arm has no --plugin-dir";; esac
case "$(cat "$A_MOG")" in *"--plugin-dir"*) ok "mogger arm has --plugin-dir";; *) bad "mogger arm has --plugin-dir";; esac
for arm in plain mogger; do
  f=$(argfile ab-alpha 1 $arm)
  txt=$(cat "$f")
  case "$txt" in *"--setting-sources
project"*) ok "$arm arm excludes the user's settings (--setting-sources project)";; *) bad "$arm arm excludes the user's settings";; esac
  case "$txt" in *"--permission-mode
acceptEdits"*) ok "$arm arm: edits allowed without prompt (acceptEdits)";; *) bad "$arm arm: acceptEdits";; esac
  case "$txt" in *"--include-hook-events"*) ok "$arm arm asks for hook events";; *) bad "$arm arm asks for hook events";; esac
  case "$txt" in *"--strict-mcp-config"*) ok "$arm arm ignores the user's MCP servers";; *) bad "$arm arm ignores MCP servers";; esac
  case "$txt" in *"--no-session-persistence"*) ok "$arm arm leaves no session behind";; *) bad "$arm arm leaves no session behind";; esac
  case "$txt" in *"--max-budget-usd
0.82"*) ok "$arm arm passes the per-trial cap (--max-budget-usd 0.82)";; *) bad "$arm arm passes the per-trial cap";; esac
  case "$txt" in *"--max-turns
9"*) ok "$arm arm passes the task's turn limit";; *) bad "$arm arm passes the task's turn limit";; esac
  case "$txt" in *"--model
sonnet"*) ok "$arm arm uses the sonnet alias";; *) bad "$arm arm uses the sonnet alias";; esac
  case "$txt" in *"--output-format
stream-json"*) ok "$arm arm reads stream-json";; *) bad "$arm arm reads stream-json";; esac
done
cat > "$SB/same.py" <<'EOF_PYC'
import glob, os, sys
d = sys.argv[1]
bad = 0
n = 0
for f in sorted(glob.glob(os.path.join(d, "*.plain.args"))):
    g = f.replace(".plain.args", ".mogger.args")
    if not os.path.exists(g):
        bad += 1
        continue
    a = open(f).read().split("\n")[3:]
    b = open(g).read().split("\n")[3:]
    if "--plugin-dir" in b:
        i = b.index("--plugin-dir")
        del b[i:i + 2]
    n += 1
    if a != b:
        bad += 1
print("%d/%d" % (n - bad, n))
EOF_PYC
same=$(python3 "$SB/same.py" "$STUB/calls" 2>&1)
eq "for all 12 pairs the two command lines match except --plugin-dir" "$same" "12/12"
eq "arm A never sees the plugin dir (24 calls, 12 with --plugin-dir)" "$(grep -l -e '--plugin-dir' "$STUB"/calls/*.args | wc -l | tr -d ' ')" "12"
eq "the mogger arm gets a plugin copy with its manifest" "$(cat "$STUB/calls/ab-alpha.1.mogger.plugin" | head -1)" "plugin-ok"
case "$(cat "$STUB/calls/ab-alpha.1.mogger.plugin")" in *"no-evals"*) ok "plugin copy has no evals/ (answer keys stay out of reach)";; *) bad "plugin copy has no evals/";; esac
case "$(cat "$STUB/calls/ab-alpha.1.mogger.plugin")" in *"has-hooks"*) ok "plugin copy keeps hooks/";; *) bad "plugin copy keeps hooks/";; esac
eq "env: the user's CLAUDE.md files are disabled in the plain arm" "$(cat "$STUB/calls/ab-alpha.1.plain.env" | tr '\n' ' ')" "CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 CLAUDE_CODE_DISABLE_CLAUDE_MDS=1 "
eq "env: same in the mogger arm" "$(cat "$STUB/calls/ab-alpha.1.mogger.env" | tr '\n' ' ')" "CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 CLAUDE_CODE_DISABLE_CLAUDE_MDS=1 "
[ -f "$PLUG/evals/SECRET-KEY.txt" ] && ok "the real plugin root was not modified" || bad "the real plugin root was not modified"

echo "== fresh workspace per trial"
eq "no trial found a leftover file from another trial" "$(cat "$STUB"/calls/*.fresh | sort -u | tr '\n' ' ')" "clean "
eq "24 distinct workspaces" "$(cat "$STUB"/calls/*.cwd | sort -u | wc -l | tr -d ' ')" "24"
eq "each workspace holds the fixture and a git dir only (no answer keys)" "$(cat "$STUB"/calls/*.ls | sort -u | tr '\n' '|')" ".git a.txt |"
eq "each workspace has a one-commit history" "$(cat "$STUB"/calls/*.git | sort -u | tr '\n' ' ')" "1 "
gone=0
for f in "$STUB"/calls/*.cwd; do [ -d "$(cat "$f")" ] && gone=$((gone+1)); done
eq "workspaces are deleted after each trial" "$gone" "0"
eq "arm B starts without mogger state (no .claude folder, no CONSTRAINTS.md)" "$(grep -l -E 'CONSTRAINTS|\.claude' "$STUB"/calls/*.ls 2>/dev/null | wc -l | tr -d ' ')" "0"

echo "== measurements per trial"
eq "cost is read from total_cost_usd" "$(pj "$LASTAB" 'sorted(set(t["cost_usd"] for t in d["trials"]))')" "[0.1]"
eq "cost source is marked as reported by the CLI" "$(pj "$LASTAB" 'sorted(set(t["cost_source"] for t in d["trials"]))')" "['reported']"
eq "tokens: input, output, cache read and cache creation" "$(pj "$LASTAB" 'd["trials"][0]["tokens"]')" "{'cache_creation': 300, 'cache_read': 5000, 'input': 1000, 'output': 200}"
eq "turns per arm come from num_turns" "$(pj "$LASTAB" 'sorted(set((t["arm"], t["turns"]) for t in d["trials"]))')" "[('mogger', 7), ('plain', 5)]"
eq "duration comes from duration_ms" "$(pj "$LASTAB" 'sorted(set(t["duration_s"] for t in d["trials"]))')" "[4.2]"
eq "subtype and is_error are kept" "$(pj "$LASTAB" 'sorted(set((t["subtype"], t["is_error"]) for t in d["trials"]))')" "[('success', False)]"
eq "every trial is graded" "$(pj "$LASTAB" 'sorted(set(t["passed"] for t in d["trials"]))')" "[True]"
eq "a transcript is saved for every trial" "$(find "$ABS/runs" -name '*.jsonl' | wc -l | tr -d ' ')" "24"
eq "hook events appear only in the mogger arm" "$(pj "$LASTAB" 'sorted(set((t["arm"], t["hook_events"]>0) for t in d["trials"]))')" "[('mogger', True), ('plain', False)]"
eq "hook script names are read from the events" "$(pj "$LASTAB" 'd["hooks"]["mogger"]["hooks"]["PreToolUse secret-guard-bash.sh"]')" "12"
eq "a hook counts once even with start and response events" "$(pj "$LASTAB" 'd["hooks"]["mogger"]["hooks"]["SessionStart session-start.sh"]')" "12"
eq "a hook without a script path is named by hook_name" "$(pj "$LASTAB" '"Stop Stop:done" in d["hooks"]["mogger"]["hooks"]')" "True"
eq "the init event lists the plugin in all mogger trials" "$(pj "$LASTAB" 'd["hooks"]["mogger"]["plugin_listed"]')" "12"
eq "the plain arm shows no plugin" "$(pj "$LASTAB" 'd["hooks"]["plain"]["plugin_listed"]')" "0"
eq "the max-budget cap used per trial is recorded" "$(pj "$LASTAB" 'sorted(set(t["cap_usd"] for t in d["trials"]))')" "[0.82]"
eq "a mogger arm that works raises no warning" "$(pj "$LASTAB" 'len(d["warnings"])')" "0"

echo "== report files"
for f in "$ABS/report.md" "$ABS/report.html" "$LASTAB"; do
  c=$(grep -c -E 'https?://' "$f")
  eq "no external URL in $(basename "$f")" "$c" "0"
done
c=$(grep -c -i -E '<script|src=|href=|url\(|@import|<link' "$ABS/report.html")
eq "report.html loads nothing (no script, src, href, url(), import, link)" "$c" "0"
OUT=$(cat "$ABS/report.html")
has "report.html is a complete page" "</html>"
has "report.html has a verdict" "<h2>Verdict</h2>"
OUT=$(cat "$ABS/report.md")
has "report.md says costs are estimates" "client-side estimate"
has "report.md names the model" "Model: sonnet"
has "report.md names the CLI version" "9.9.9"
has "report.md names the plugin version" "Plugin version: 0.0.0"
has "report.md explains how a claim is made" "excludes zero"
has "report.md tells that tasks 3-6 favour mogger" "favour mogger by design"
has "report.md explains cost per successful task" "divided by the number of correct trials"
has "report.md justifies the bootstrap" "seeded bootstrap"
OUT=$(cd "$PROJ" && bash "$EV" ab report 2>&1); RC=$?
eq "report prints from the saved result" "$RC" "0"
has "report shows the verdict" "VERDICT"
has "report shows hooks fired in arm B" "Hooks in the mogger arm: 72 hook events in 12 of 12 trials."
has "report names a hook" "PreToolUse secret-guard-bash.sh: 12"
has "report says the plain arm has no hook events" "Hook events in the plain arm (must be 0): 0"
has "report shows per-task rows" "- ab-alpha:"
has "report shows the loud permission-mode note" "Hooks under that mode are UNVERIFIED"

echo "== status"
abx status
eq "status exits 0" "$RC" "0"
has "status: not running" "running: no"
has "status: progress is shown" "progress: 24 of 24 trials"
has "status: last result is shown" "last result:"

# ================================================================ statistics on known inputs
echo "== statistics: known inputs"
cat > "$SB/math.py" <<'EOF_PYMATH'
import json, math, os, sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import ab, common

def check(name, cond, extra=""):
    print(("ok   " if cond else "FAIL ") + name + ("" if cond or not extra else "  :: " + str(extra)))

def near(a, b, tol=1e-9):
    return a is not None and abs(a - b) <= tol

def T(task, arm, rep, cost, passed, status="ok", turns=5):
    return {"task": task, "arm": arm, "repeat": rep, "cost_usd": cost, "passed": (None if status != "ok" else passed),
            "status": status, "turns": turns, "tokens": {"input": 100, "output": 10, "cache_read": 0, "cache_creation": 0}, "duration_s": 1.0}

names = ["t1", "t2", "t3", "t4", "t5", "t6"]

def build(fa, fb, n_rep=2, succ_a=lambda i: True, succ_b=lambda i: True, jitter=0.01):
    out, i = [], 0
    for r in range(1, n_rep + 1):
        for t in names:
            a = 1.0 + jitter * i
            out.append(T(t, "plain", r, a, succ_a(i)))
            out.append(T(t, "mogger", r, fb(a, i), succ_b(i)))
            i += 1
    return out

lo, hi = common.wilson(8, 10)
check("wilson 8/10 low", near(lo, 0.4902, 0.001), lo)
check("wilson 8/10 high", near(hi, 0.9433, 0.001), hi)
lo, hi = common.wilson(0, 10)
check("wilson 0/10 starts at 0", lo == 0.0)
check("wilson 0/10 high", near(hi, 0.2775, 0.001), hi)
check("percentile median", ab.percentile([1, 2, 3, 4, 5], 50) == 3)
check("percentile q25", ab.percentile([1, 2, 3, 4, 5], 25) == 2)
check("percentile ends", ab.percentile([1, 2, 3, 4, 5], 0) == 1 and ab.percentile([1, 2, 3, 4, 5], 100) == 5)
check("percentile interpolates", near(ab.percentile([1, 2], 50), 1.5))
check("cost per success = cost / successes", near(ab.cost_per_success(10.0, 4), 2.5))
check("cost per success with no success is undefined", ab.cost_per_success(5.0, 0) is None)

c = ab.cell([T("t1", "plain", 1, 0.1, True), T("t1", "plain", 2, 0.2, False), T("t2", "plain", 1, 0.3, True),
             T("t2", "plain", 2, 0.4, None, status="api_error")])
check("cell: 3 scored of 4", c["n"] == 3 and c["trials"] == 4)
check("cell: 2 correct", c["k"] == 2)
check("cell: rate 2/3", near(c["rate"], 2 / 3.0))
check("cell: plumbing counted apart", c["plumbing"] == {"api_error": 1})
check("cell: cost of the plumbing trial is still counted", near(c["total_cost"], 1.0))
check("cell: mean cost over all 4 trials", near(c["mean_cost"], 0.25))

tr = [T("t1", "plain", 1, 0.2, True), T("t1", "plain", 2, 0.2, False), T("t1", "plain", 3, 0.6, None, status="api_error")]
an = ab.analyze(tr, "s", 200)
check("analyze: cost per success counts wrong and failed runs", near(an["arms"]["plain"]["cost_per_success"], 1.0))
check("analyze: plumbing excluded from the success rate (1 of 2)", near(an["arms"]["plain"]["rate"], 0.5))
check("analyze: wilson CI is the common.wilson CI", an["arms"]["plain"]["ci95"] == list(common.wilson(1, 2)))

pairs4 = [{"task": "t", "repeat": i, "a_cost": 1.0, "b_cost": 1.2, "a_valid": True, "b_valid": True, "a_succ": 1, "b_succ": 1} for i in range(4)]
r, cd, sd = ab.pair_stats(pairs4)
check("pair_stats: +20% cost per success", near(r, 0.2), r)
check("pair_stats: +0.2 mean cost per trial", near(cd, 0.2), cd)
check("pair_stats: no success change", near(sd, 0.0))
for i in (2, 3):
    pairs4[i]["b_succ"] = 0
r, cd, sd = ab.pair_stats(pairs4)
check("pair_stats: half the successes doubles cost per success", near(r, 1.4), r)
check("pair_stats: success difference -0.5", near(sd, -0.5), sd)

mix = [T("t1", "plain", 1, 1.0, True), T("t1", "mogger", 1, 1.0, True), T("t2", "plain", 1, 1.0, True)]
check("make_pairs: only trials with a partner", len(ab.make_pairs(mix)) == 1)
check("analyze: counts the unpaired trial", ab.analyze(mix, "s", 100)["unpaired_trials"] == 1)

p1 = ab.paired_bootstrap(ab.make_pairs(build(None, lambda a, i: a * (1.3 if i >= 6 else 0.8))), "S", 300)
p2 = ab.paired_bootstrap(ab.make_pairs(build(None, lambda a, i: a * (1.3 if i >= 6 else 0.8))), "S", 300)
p3 = ab.paired_bootstrap(ab.make_pairs(build(None, lambda a, i: a * (1.3 if i >= 6 else 0.8))), "T", 300)
check("bootstrap: same seed, same interval", p1["ci"] == p2["ci"])
check("bootstrap: another seed, another interval", p1["ci"] != p3["ci"])

an = ab.analyze(build(None, lambda a, i: a * 1.2), "S", 300)
check("verdict: B always 20% dearer -> a claim", an["verdict"]["claim_cost"] is True)
check("verdict: wording says 20% more", "Mogger cost 20% more per successful task" in an["verdict"]["cost"], an["verdict"]["cost"])
check("verdict: wording gives the CI", "95% CI +20% to +20%" in an["verdict"]["cost"], an["verdict"]["cost"])
an = ab.analyze(build(None, lambda a, i: a * 0.7), "S", 300)
check("verdict: B always 30% cheaper -> a claim", an["verdict"]["claim_cost"] is True)
check("verdict: wording says 30% less", "Mogger cost 30% less per successful task" in an["verdict"]["cost"], an["verdict"]["cost"])
an = ab.analyze(build(None, lambda a, i: a * (1.3 if i >= 6 else 0.7)), "S", 300)
check("verdict: noisy -> no claim", an["verdict"]["claim_cost"] is False, an["verdict"]["cost"])
check("verdict: noisy wording", "within noise: no claim" in an["verdict"]["cost"])
check("verdict: noisy wording makes no savings claim", "Mogger cost" not in an["verdict"]["cost"] and " less per" not in an["verdict"]["cost"])
an = ab.analyze(build(None, lambda a, i: a * (0.7 if i < 6 else 1.2)), "S", 300)
pt = an["paired"]["point"]["rel_cost_per_success"]
check("verdict: negative point estimate inside noise", pt < 0 and an["verdict"]["claim_cost"] is False, (pt, an["verdict"]["cost"]))
check("verdict: negative point estimate is not called a saving", " less per" not in an["verdict"]["cost"] and "Mogger cost" not in an["verdict"]["cost"])
an = ab.analyze(build(None, lambda a, i: a * 1.2)[:6], "S", 300)
check("verdict: 3 pairs -> too few", "Too few paired results (3, need 6). No claim." in an["verdict"]["cost"], an["verdict"]["cost"])
an = ab.analyze(build(None, lambda a, i: a, succ_a=lambda i: True, succ_b=lambda i: i < 2), "S", 300)
check("verdict: success drop is claimed", an["verdict"]["claim_success"] is True, an["verdict"]["success"])
check("verdict: success wording in points", "Mogger changed the success rate by -83 points" in an["verdict"]["success"], an["verdict"]["success"])
an = ab.analyze(build(None, lambda a, i: a), "S", 300)
check("verdict: equal success -> no success claim", an["verdict"]["claim_success"] is False and "within noise: no claim" in an["verdict"]["success"])
an = ab.analyze(build(None, lambda a, i: a * 1.2), "S", 300, partial=True)
check("verdict: partial run is flagged", "PARTIAL RUN" in an["verdict"]["cost"])

tr = build(None, lambda a, i: a * 1.0)
for t in tr:
    if t["arm"] == "mogger" and t["task"] in ("t1", "t2", "t3") and t["repeat"] == 1:
        t["status"], t["passed"], t["cost_usd"] = "api_error", None, 0.5
an = ab.analyze(tr, "S", 300)
check("plumbing: 3 mogger trials dropped from scoring", an["arms"]["mogger"]["n"] == 9 and an["arms"]["mogger"]["plumbing_n"] == 3)
check("plumbing: their cost is still in the total", near(an["arms"]["mogger"]["total_cost"], sum(t["cost_usd"] for t in tr if t["arm"] == "mogger")))
check("plumbing: the plain arm is whole", an["arms"]["plain"]["n"] == 12)
check("plumbing: only pairs scorable in both arms count", an["valid_pairs"] == 9)
check("plumbing: success rate of the mogger arm is over scored trials only", near(an["arms"]["mogger"]["rate"], 1.0))

check("estimate: plain trial on sonnet = 0.38", near(ab.trial_est_usd("plain", "sonnet"), 0.38, 1e-9))
check("estimate: mogger trial on sonnet = 0.41", near(ab.trial_est_usd("mogger", "sonnet"), 0.41, 1e-9))
check("estimate: per-trial cap = 0.82", near(ab.trial_cap_usd("sonnet"), 0.82))
check("estimate: haiku is cheaper", ab.trial_est_usd("plain", "haiku") < ab.trial_est_usd("plain", "sonnet"))

ids = [("t%d" % k, r) for k in range(100) for r in (1, 2)]
firsts = [ab.arm_order("seed", t, r)[0] for t, r in ids]
check("arm order: reproducible", firsts == [ab.arm_order("seed", t, r)[0] for t, r in ids])
check("arm order: changes with the seed", firsts != [ab.arm_order("seed2", t, r)[0] for t, r in ids])
check("arm order: roughly balanced over 200 pairs", 70 <= firsts.count("plain") <= 130, firsts.count("plain"))
check("arm order: always one of each arm", all(sorted(ab.arm_order("s", t, r)) == ["mogger", "plain"] for t, r in ids))

tasks = [{"id": "x%d" % i} for i in range(4)]
plan = ab.build_plan(tasks, 3, "s")
check("plan: 24 trials", len(plan) == 24)
check("plan: repeat-major (never repeat 2 before repeat 1 is done)", [p["repeat"] for p in plan] == sorted(p["repeat"] for p in plan))
check("plan: the two arms of a task run back to back", all(plan[i]["task"] is plan[i + 1]["task"] and plan[i]["repeat"] == plan[i + 1]["repeat"] and plan[i]["arm"] != plan[i + 1]["arm"] for i in range(0, 24, 2)))

cap = ab.Cap(1.0)
check("cap: first start ok", cap.try_start(0.4))
check("cap: second start ok (0.8 <= 1.0)", cap.try_start(0.4))
check("cap: third start refused (1.2 > 1.0)", not cap.try_start(0.4))
cap.finish(0.4, 0.1)
check("cap: refusal is sticky", not cap.try_start(0.01))
cap = ab.Cap(1.0)
cap.try_start(0.5)
cap.finish(0.5, 1.0)
check("cap: spent >= cap stops everything", not cap.try_start(0.001))
cap = ab.Cap(1.0)
check("cap: in-flight estimates count", cap.try_start(0.6) and not cap.try_start(0.6))

lines = [json.dumps({"type": "system", "subtype": "init", "claude_code_version": "1.2.3", "plugins": [{"name": "mogger", "path": "/p"}]}),
         json.dumps({"type": "system", "subtype": "hook_started", "hook_id": "a", "hook_event": "PreToolUse", "hook_name": "PreToolUse:Bash", "command": "bash /x/scripts/cost-cap.sh"}),
         json.dumps({"type": "system", "subtype": "hook_response", "hook_id": "a", "hook_event": "PreToolUse", "hook_name": "PreToolUse:Bash", "outcome": "success"}),
         json.dumps({"type": "system", "subtype": "hook_response", "hook_id": "b", "hook_event": "Stop", "hook_name": "Stop:x"}),
         "not json", json.dumps({"type": "result", "subtype": "success", "result": "ok", "total_cost_usd": 0.5, "usage": {"input_tokens": 3, "output_tokens": 4, "cache_read_input_tokens": 5, "cache_creation_input_tokens": 6}})]
ps = ab.parse_trial_stream(lines)
check("stream: CLI version", ps["cli_version"] == "1.2.3")
check("stream: plugins from init", ps["plugins"] == ["mogger"])
check("stream: hook counted once per id", ps["hooks"] == {"PreToolUse cost-cap.sh": 1, "Stop Stop:x": 1}, ps["hooks"])
check("stream: all hook events counted", ps["hook_events"] == 3)
check("stream: usage fields", ab.usage_of(ps["info"]["result"]) == {"input": 3, "output": 4, "cache_read": 5, "cache_creation": 6})
EOF_PYMATH
python3 "$SB/math.py" "$ROOT/scripts/eval" > "$SB/math.out" 2>&1
while IFS= read -r line; do
  case "$line" in
    "ok   "*) ok "${line#ok   }" ;;
    "FAIL "*) bad "${line#FAIL }" ;;
    *) printf '       %s\n' "$line" ;;
  esac
done < "$SB/math.out"

echo "== report --input on known data (CLI path)"
python3 - "$SB/known.json" <<'EOF_PYK'
import json, sys
tr = []
names = ["t1", "t2", "t3", "t4", "t5", "t6"]
i = 0
for r in (1, 2):
    for t in names:
        a = 1.0 + 0.01 * i
        tr.append({"task": t, "arm": "plain", "repeat": r, "cost_usd": a, "status": "ok", "passed": True, "turns": 5, "tokens": {"input": 100, "output": 10}, "duration_s": 1})
        tr.append({"task": t, "arm": "mogger", "repeat": r, "cost_usd": a * 1.2, "status": "ok", "passed": True, "turns": 6, "tokens": {"input": 110, "output": 10}, "duration_s": 1})
        i += 1
json.dump({"trials": tr, "model": "sonnet"}, open(sys.argv[1], "w"))
EOF_PYK
reset_project
abx report --input "$SB/known.json"
eq "report --input exits 0" "$RC" "0"
has "report --input: B 20% dearer per successful task is claimed" "Mogger cost 20% more per successful task (95% CI +20% to +20%)."
has "report --input: success is equal, no claim" "The success difference is within noise: no claim."
has "report --input: totals" "Arm plain: 12 trials, 12 scored, 12 correct (100%"
eq "report --input wrote the paired cost difference" "$(pj "$LASTAB" '"%.3f" % d["analysis"]["paired"]["point"]["cost_diff_per_trial"]')" "0.211"
OUT=$(cd "$PROJ" && MOGGER_EVAL_PLUGIN_ROOT="$ROOT" MOGGER_EVAL_DIR="$ROOT/evals" bash "$EV" ab report --input "$SB/known.json" 2>&1); RC=$?
has "report includes the overhead facts from context-cost.sh" "Overhead facts (scripts/context-cost.sh"
has "report includes measured input tokens per arm" "Measured: mean input tokens per trial plain 100, mogger 110."

# ================================================================ plumbing in a real run
echo "== plumbing: counted in cost, kept out of quality"
resetstub; reset_project
printf 'apierror' > "$STUB/mode.ab-alpha.mogger"
printf 'truncated' > "$STUB/mode.ab-beta.plain"
printf '0.25' > "$STUB/cost.ab-alpha.mogger"
abx run --budget 50 --repeats 1 --jobs 2
eq "run with failing trials still exits 0" "$RC" "0"
eq "the API-error trial has no pass/fail" "$(pj "$LASTAB" '[t["passed"] for t in d["trials"] if t["task"]=="ab-alpha" and t["arm"]=="mogger"][0]')" "None"
eq "the API-error trial is classified as plumbing" "$(pj "$LASTAB" '[t["status"] for t in d["trials"] if t["task"]=="ab-alpha" and t["arm"]=="mogger"][0]')" "api_error"
eq "the max-turns trial is classified as plumbing (truncated)" "$(pj "$LASTAB" '[t["status"] for t in d["trials"] if t["task"]=="ab-beta" and t["arm"]=="plain"][0]')" "truncated"
eq "plumbing trials are not scored: mogger arm n=5 of 6" "$(pj "$LASTAB" 'd["analysis"]["arms"]["mogger"]["n"]')" "5"
eq "plumbing trials are not scored: plain arm n=5 of 6" "$(pj "$LASTAB" 'd["analysis"]["arms"]["plain"]["n"]')" "5"
eq "plumbing is listed by kind" "$(pj "$LASTAB" 'd["analysis"]["arms"]["mogger"]["plumbing"]')" "{'api_error': 1}"
eq "plumbing cost counts in the total (5 x 0.10 + 0.25)" "$(pj "$LASTAB" '"%.2f" % d["analysis"]["arms"]["mogger"]["total_cost"]')" "0.75"
eq "success rate is over scored trials only (5/5)" "$(pj "$LASTAB" 'd["analysis"]["arms"]["mogger"]["rate"]')" "1.0"
eq "cost per successful task includes the failed run's cost (0.75 / 5)" "$(pj "$LASTAB" '"%.2f" % d["analysis"]["arms"]["mogger"]["cost_per_success"]')" "0.15"
eq "only pairs scorable in both arms count (4 of 6)" "$(pj "$LASTAB" 'd["analysis"]["valid_pairs"]')" "4"
OUT=$(cd "$PROJ" && bash "$EV" ab report 2>&1)
has "report lists infrastructure failures apart" "Infrastructure failures (not scored, cost counted): api_error 1."
has "too few scorable pairs: no claim" "Too few paired results (4, need 6). No claim."

echo "== a wrong answer is a failure, not plumbing"
resetstub; reset_project
printf 'nope' > "$STUB/ans.ab-gamma.mogger"
abx run --budget 50 --repeats 1 --jobs 2
eq "a wrong answer is graded as a fail" "$(pj "$LASTAB" '[t["passed"] for t in d["trials"] if t["task"]=="ab-gamma" and t["arm"]=="mogger"][0]')" "False"
eq "a wrong answer is still scored (status ok)" "$(pj "$LASTAB" '[t["status"] for t in d["trials"] if t["task"]=="ab-gamma" and t["arm"]=="mogger"][0]')" "ok"
eq "mogger arm: 5 of 6 correct" "$(pj "$LASTAB" 'd["analysis"]["arms"]["mogger"]["k"]')" "5"
eq "plain arm: 6 of 6 correct" "$(pj "$LASTAB" 'd["analysis"]["arms"]["plain"]["k"]')" "6"

echo "== timeout is plumbing"
resetstub; reset_project
printf 'timeout' > "$STUB/mode.ab-delta.plain"
MOGGER_AB_TIMEOUT=2 abx run --budget 50 --repeats 1 --jobs 2 --tasks ab-delta
eq "run with a timed-out trial exits 0" "$RC" "0"
eq "the timed-out trial is classified as timeout" "$(pj "$LASTAB" '[t["status"] for t in d["trials"] if t["arm"]=="plain"][0]')" "timeout"
eq "the other arm is unaffected" "$(pj "$LASTAB" '[t["status"] for t in d["trials"] if t["arm"]=="mogger"][0]')" "ok"

# ================================================================ hard cap and partial runs
echo "== hard total cap and partial results"
resetstub; reset_project
printf '0.08' > "$STUB/cost"
MOGGER_AB_EST_IN=30000 MOGGER_AB_EST_OUT=4000 MOGGER_AB_EST_EXTRA_IN=0 abx run --budget 0.45 --repeats 3 --jobs 1
eq "a capped run exits 0" "$RC" "0"
eq "5 trials ran before the cap stopped the run (4 x 0.08 + 0.10 <= 0.45 < 5 x 0.08 + 0.10)" "$(pj "$LASTAB" 'len(d["trials"])')" "5"
eq "total spend stays under the cap" "$(pj "$LASTAB" 'd["spent_usd"] <= 0.45')" "True"
eq "the result is flagged partial" "$(pj "$LASTAB" 'd["partial"]')" "True"
eq "skipped trials are counted (36 planned, 5 ran)" "$(pj "$LASTAB" '(d["planned"], d["skipped"])')" "(36, 31)"
OUT=$(cd "$PROJ" && bash "$EV" ab report 2>&1)
has "report says PARTIAL" "PARTIAL RESULTS: 5 of 36 planned trials ran"
has "the verdict carries the partial flag or too-few note" "No claim."
has "a partial warning is listed" "the spend cap stopped the run"
eq "partial run: warning about the unpaired trial" "$(pj "$LASTAB" 'any("no partner" in w for w in d["warnings"])')" "True"
eq "partial run is a prefix of the plan: all trials are repeat 1" "$(pj "$LASTAB" 'sorted(set(t["repeat"] for t in d["trials"]))')" "[1]"
eq "partial run covers the first tasks in BOTH arms (2 whole pairs)" "$(pj "$LASTAB" 'sorted(set(t["task"] for t in d["trials"] if sum(1 for u in d["trials"] if u["task"]==t["task"])==2))')" "['ab-alpha', 'ab-beta']"
FIRST=$(head -1 "$STUB/order.log")
eq "the per-trial cap never exceeds the money left (first call)" "$(grep -A1 'max-budget-usd' "$STUB/calls/$FIRST.args" | tail -1)" "0.45"
OUT=$(cd "$PROJ" && bash "$EV" ab status 2>&1)
has "status says PARTIAL" "PARTIAL"
has "status shows spend against the cap" "of \$0.45"
eq "trials.jsonl logs trials as they finish" "$(wc -l < "$ABS/trials.jsonl" | tr -d ' ')" "5"

echo "== cap with parallel jobs"
resetstub; reset_project
printf '0.08' > "$STUB/cost"
MOGGER_AB_EST_IN=30000 MOGGER_AB_EST_OUT=4000 MOGGER_AB_EST_EXTRA_IN=0 abx run --budget 0.45 --repeats 3 --jobs 2
eq "parallel capped run exits 0" "$RC" "0"
eq "parallel capped run stays under the cap" "$(pj "$LASTAB" 'd["spent_usd"] <= 0.45')" "True"
eq "parallel capped run is partial" "$(pj "$LASTAB" 'd["partial"]')" "True"
eq "parallel capped run never starts more trials than the cap allows" "$(pj "$LASTAB" 'len(d["trials"]) <= 5')" "True"
resetstub; reset_project
MOGGER_AB_EST_IN=300000 abx run --budget 0.2 --repeats 1 --jobs 2
eq "a cap below one trial's estimate starts no trial" "$RC" "0"
[ ! -d "$STUB/calls" ] && ok "tiny cap: no trial was launched" || bad "tiny cap: no trial was launched"
eq "...and reports zero trials as partial" "$(pj "$LASTAB" '(len(d["trials"]), d["partial"])')" "(0, True)"

# ================================================================ isolation warnings
echo "== warnings: isolation and missing hooks"
resetstub; reset_project
touch "$STUB/nohooks"
abx run --budget 50 --repeats 1 --jobs 2 --tasks ab-alpha
OUT=$(cd "$PROJ" && bash "$EV" ab report 2>&1)
has "no hook events in arm B is called out" "NO HOOK EVENTS in the mogger arm"
has "...and says arm B has no mogger enforcement" "NO mogger enforcement"
resetstub; reset_project
touch "$STUB/leak"
abx run --budget 50 --repeats 1 --jobs 2 --tasks ab-alpha
OUT=$(cd "$PROJ" && bash "$EV" ab report 2>&1)
has "hook events in the plain arm are called out" "ISOLATION BROKEN"
resetstub; reset_project
MOGGER_EVAL_SETTING_SOURCES= abx run --budget 50 --repeats 1 --jobs 2 --tasks ab-alpha
case "$(cat "$(argfile ab-alpha 1 plain)")" in *"--setting-sources"*) bad "empty MOGGER_EVAL_SETTING_SOURCES drops the flag";; *) ok "empty MOGGER_EVAL_SETTING_SOURCES drops the flag";; esac
OUT=$(cd "$PROJ" && bash "$EV" ab report 2>&1)
has "isolation off is warned" "ISOLATION OFF"

echo "== options: model, effort, tasks, seed"
resetstub; reset_project
abx run --budget 50 --repeats 1 --jobs 2 --tasks alpha,ab-beta --model haiku --effort low --seed zzz
eq "short task names work (alpha = ab-alpha)" "$(pj "$LASTAB" 'sorted(set(t["task"] for t in d["trials"]))')" "['ab-alpha', 'ab-beta']"
case "$(cat "$(argfile ab-alpha 1 plain)")" in *"--model
haiku"*) ok "--model is passed to both arms";; *) bad "--model is passed to both arms";; esac
case "$(cat "$(argfile ab-alpha 1 mogger)")" in *"--effort
low"*) ok "--effort is passed to both arms";; *) bad "--effort is passed to both arms";; esac
eq "the seed is recorded" "$(pj "$LASTAB" 'd["seed"]')" "zzz"
eq "model and effort are recorded" "$(pj "$LASTAB" '(d["model"], d["effort"])')" "('haiku', 'low')"
resetstub; reset_project
abx run --budget 50 --repeats 1 --jobs 1 --tasks ab-alpha,ab-beta,ab-gamma --seed abc
cp "$STUB/order.log" "$SB/order1.log"
resetstub; reset_project
abx run --budget 50 --repeats 1 --jobs 1 --tasks ab-alpha,ab-beta,ab-gamma --seed abc
eq "the same seed gives the same start order in a real run" "$(cat "$STUB/order.log")" "$(cat "$SB/order1.log")"
resetstub; reset_project
abx run --budget 50 --repeats 1 --jobs 1 --tasks ab-alpha,ab-beta,ab-gamma --seed abd
[ "$(cat "$STUB/order.log")" != "$(cat "$SB/order1.log")" ] && ok "another seed gives another start order" || bad "another seed gives another start order"
eq "the run order follows the plan: task pairs stay together" "$(sed -e 's/\.[0-9]*\.[^.]*$//' "$STUB/order.log" | uniq -c | awk '{print $1}' | sort -u | tr '\n' ' ')" "2 "

# ================================================================ background run
echo "== background run: pid file"
resetstub; reset_project
printf '1' > "$STUB/delay"
abx run --budget 50 --repeats 1 --jobs 1 --tasks ab-alpha --background
eq "background start exits 0" "$RC" "0"
has "background start says so" "Started in the background"
[ -s "$ABS/running.pid" ] && ok "pid file written" || bad "pid file written"
PIDV=$(tr -dc '0-9' < "$ABS/running.pid" 2>/dev/null)
kill -0 "$PIDV" 2>/dev/null && ok "the pid in the file is alive" || bad "the pid in the file is alive"
abx status
has "status: running" "running: yes"
abx run --budget 50 --repeats 1 --tasks ab-alpha
eq "a second run is refused while one is going (exit 2)" "$RC" "2"
has "refusal names the running pid" "already going"
n=0
while [ -f "$ABS/running.pid" ] && [ "$n" -lt 150 ]; do sleep 0.2; n=$((n+1)); done
[ ! -f "$ABS/running.pid" ] && ok "pid file removed when the background run ends" || bad "pid file removed when the background run ends"
[ -f "$LASTAB" ] && ok "background run wrote last-ab.json" || bad "background run wrote last-ab.json"
[ -f "$ABS/run.log" ] && ok "background run wrote run.log" || bad "background run wrote run.log"
eq "background run ran both arms" "$(pj "$LASTAB" 'len(d["trials"])')" "2"
abx status
has "status: no longer running" "running: no"
has "status: finished" "(finished)"

echo "== report and status with no results"
reset_project
abx report
has "report with no results says so" "No A/B results yet"
abx status
has "status with no results says so" "progress: no run yet"

echo
echo "evals-ab tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
