#!/usr/bin/env bash
# Tests for scripts/mogger-eval.sh (the eval engine). Run: bash tests/evals.test.sh
# No API, no network: a stub `claude` (bash) writes canned stream-json per task id.
# Self-contained temp sandbox; bash 3.2 / BSD userland safe.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EV="$ROOT/scripts/mogger-eval.sh"
PASS=0; FAIL=0
SB=$(mktemp -d)
trap 'rm -rf "$SB"' EXIT
export PYTHONDONTWRITEBYTECODE=1

ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
has()   { case "$OUT" in *"$2"*) ok "$1";; *) bad "$1"; printf '       missing: [%s]\n       in: %s\n' "$2" "$(printf '%s' "$OUT" | head -c 600)";; esac; }
hasnt() { case "$OUT" in *"$2"*) bad "$1"; printf '       unexpected: [%s]\n' "$2";; *) ok "$1";; esac; }
eq()    { [ "$2" = "$3" ] && ok "$1" || { bad "$1"; printf '       want [%s] got [%s]\n' "$3" "$2"; }; }
w() { mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" > "$1"; }

# ---------------------------------------------------------------- sandbox
PLUG="$SB/plugin"; PROJ="$SB/proj"; STUB="$SB/stub"; BIN="$SB/bin"
mkdir -p "$PROJ" "$STUB" "$BIN"
export STUB_DIR="$STUB"
export MOGGER_CLAUDE_BIN="$BIN/claude"
export MOGGER_EVAL_PLUGIN_ROOT="$PLUG"
unset MOGGER_EVAL_DIR MOGGER_EVAL_STATE_DIR MOGGER_EVAL_PRICING

w "$PLUG/.claude-plugin/plugin.json" '{"name":"mogger","version":"0.0.0"}'
w "$PLUG/templates/pricing.json" '{"models":{"haiku":{"input_per_mtok":1.00,"output_per_mtok":5.00},"sonnet":{"input_per_mtok":2.00,"output_per_mtok":10.00},"opus":{"input_per_mtok":4.00,"output_per_mtok":20.00}}}'
mkdir -p "$PLUG/agents" "$PLUG/evals/tasks"
printf '%s\n' '---' 'name: explorer' 'description: Finds things in the codebase.' 'tools: Read, Grep' 'model: haiku' 'effort: low' '---' 'You find things.' '' '## Before you finish: log the savings estimate' 'run the script' > "$PLUG/agents/explorer.md"
printf '%s\n' '---' 'name: boss' 'description: Plans work.' 'model: sonnet' '---' 'You plan.' > "$PLUG/agents/boss.md"
w "$PLUG/skills/alpha/SKILL.md" "$(printf '%s\n' '---' 'name: alpha' 'description: Alpha thing.' '---' '' '# alpha' 'Body one.')"
w "$PLUG/skills/beta/SKILL.md" "$(printf '%s\n' '---' 'name: beta' 'description: Beta thing.' '---' '' '# beta' 'Body two.')"

mk_evals() {  # mk_evals <dir>: fixtures + trigger prompts (tasks are written per scenario)
  w "$1/fixtures/mini/a.txt" 'nothing to see here'
  w "$1/fixtures/mini/b.txt" 'lorem ipsum'
  w "$1/fixtures/shop/README.md" 'shop fixture'
  local s i out=""
  {
    printf '{"skills":{'
    for s in alpha beta; do
      printf '"%s":{"should":[' "$s"
      for i in 0 1 2 3 4 5; do printf '"Please help me with the %s situation number %s right now",' "$s" "$i" ; done | sed 's/,$//'
      printf '],"should_not":['
      for i in 0 1 2 3 4 5; do printf '"Tell me something unrelated to %s, item %s, thanks a lot",' "$s" "$i"; done | sed 's/,$//'
      printf ']}'
      [ "$s" = alpha ] && printf ','
    done
    printf '}}\n'
  } > "$1/triggers.json"
}
mk_evals "$PLUG/evals"
cat > "$PLUG/evals/tasks/explorer.json" <<'EOF'
{"agent":"explorer","tasks":[
 {"id":"t1","agent":"explorer","fixture":"mini","prompt":"Where is alpha?","why_hard":"decoys","grader":{"type":"contains_all","values":["alpha-7"]},"gold":{"text":"alpha-7"},"bad":{"text":"nope"}},
 {"id":"t2","agent":"explorer","fixture":"mini","prompt":"Where is beta?","why_hard":"decoys","grader":{"type":"contains_all","values":["beta-8"]},"gold":{"text":"beta-8"},"bad":{"text":"nope"}},
 {"id":"t3","agent":"explorer","fixture":"mini","prompt":"Where is gamma?","why_hard":"decoys","grader":{"type":"contains_all","values":["gamma-9"]},"gold":{"text":"gamma-9"},"bad":{"text":"nope"}}
]}
EOF

# a second evals dir per scenario
mk_variant() {  # mk_variant <dir> <tasks-json-file>
  mk_evals "$1"; mkdir -p "$1/tasks"; cp "$2" "$1/tasks/explorer.json"
}
cat > "$SB/flaky.json" <<'EOF'
{"agent":"explorer","tasks":[
 {"id":"f1","agent":"explorer","fixture":"mini","prompt":"flaky","why_hard":"grader that changes its mind","grader":{"type":"run","cmd":["python3","-c","import os,sys; p='.ran_once'; e=os.path.exists(p); open(p,'w').close(); sys.exit(1 if e else 0)"]},"gold":{"text":"x"},"bad":{"text":"y"}}
]}
EOF
cat > "$SB/plumb.json" <<'EOF'
{"agent":"explorer","tasks":[
 {"id":"p1","agent":"explorer","fixture":"mini","prompt":"a","why_hard":"w","grader":{"type":"contains_all","values":["fine"]},"gold":{"text":"fine"},"bad":{"text":"no"}},
 {"id":"p2","agent":"explorer","fixture":"mini","prompt":"b","why_hard":"w","grader":{"type":"contains_all","values":["fine"]},"gold":{"text":"fine"},"bad":{"text":"no"}},
 {"id":"p3","agent":"explorer","fixture":"mini","prompt":"c","why_hard":"w","grader":{"type":"contains_all","values":["fine"]},"gold":{"text":"fine"},"bad":{"text":"no"}},
 {"id":"p4","agent":"explorer","fixture":"mini","prompt":"d","why_hard":"w","grader":{"type":"contains_all","values":["fine"]},"gold":{"text":"fine"},"bad":{"text":"no"}},
 {"id":"p5","agent":"explorer","fixture":"mini","prompt":"e","why_hard":"w","grader":{"type":"contains_all","values":["fine"]},"gold":{"text":"fine"},"bad":{"text":"no"}}
]}
EOF
cat > "$SB/iso.json" <<'EOF'
{"agent":"explorer","tasks":[
 {"id":"i1","agent":"explorer","fixture":"mini","prompt":"first","why_hard":"w","grader":{"type":"contains_all","values":["alpha-7"]},"gold":{"text":"alpha-7"},"bad":{"text":"no"}},
 {"id":"i2","agent":"explorer","fixture":"mini","prompt":"second","why_hard":"w","grader":{"type":"contains_all","values":["beta-8"]},"gold":{"text":"beta-8"},"bad":{"text":"no"}},
 {"id":"i3","agent":"explorer","fixture":"mini","prompt":"third","why_hard":"w","grader":{"type":"contains_all","values":["gamma-9"]},"gold":{"text":"gamma-9"},"bad":{"text":"no"}}
]}
EOF
mk_variant "$SB/ev_flaky" "$SB/flaky.json"
mk_variant "$SB/ev_plumb" "$SB/plumb.json"
mk_variant "$SB/ev_iso" "$SB/iso.json"

# ---------------------------------------------------------------- the stub claude
cat > "$BIN/claude" <<'EOF'
#!/usr/bin/env bash
# stub claude: canned stream-json chosen by MOGGER_EVAL_TASK_ID. Files in $STUB_DIR.
S="$STUB_DIR"
allargs="$*"
model=""; plugin=""; prompt=""
while [ $# -gt 0 ]; do
  case "$1" in
    -p) prompt="$2"; shift ;;
    --model) model="$2"; shift ;;
    --plugin-dir) plugin="$2"; shift ;;
  esac
  shift
done
id="${MOGGER_EVAL_TASK_ID:-none}"; rep="${MOGGER_EVAL_TRIAL:-1}"
tier=sonnet; case "$model" in *haiku*) tier=haiku ;; esac
echo "$id $tier $PWD" >> "$S/calls.log"
printf '%s|%s\n' "$id" "$allargs" >> "$S/args.log"
case "$id" in proposer-*) printf '%s' "$prompt" > "$S/proposer_prompt.${id#proposer-}" ;; esac
if [ -f "$S/side.$id.sh" ]; then . "$S/side.$id.sh"; fi
if [ -f "$S/delay" ]; then sleep "$(cat "$S/delay")"; fi
mode=normal; [ -f "$S/mode.$id" ] && mode=$(cat "$S/mode.$id")
cost=0.01; [ -f "$S/cost" ] && cost=$(cat "$S/cost")
emit_result() {  # emit_result <subtype> <is_error> <text-file-or-empty>
  python3 - "$1" "$2" "$3" "$cost" <<'PYX'
import json, sys
sub, iserr, tf, cost = sys.argv[1:5]
text = open(tf).read() if tf and tf != "-" else ""
print(json.dumps({"type": "result", "subtype": sub, "is_error": iserr == "1", "result": text, "num_turns": 1,
                  "stop_reason": "end_turn", "total_cost_usd": float(cost), "usage": {"input_tokens": 10, "output_tokens": 5}}))
PYX
}
echo '{"type":"system","subtype":"init","model":"stub"}'
case "$mode" in
  timeout) sleep 30; exit 0 ;;
  empty) emit_result success 0 -; exit 0 ;;
  apierror) emit_result error_during_execution 1 -; exit 0 ;;
  truncated) printf 'partial' > "$S/tmp.txt"; emit_result error_max_turns 0 "$S/tmp.txt"; exit 0 ;;
esac
case "$id" in
  trig.*)
    spec=""; [ -f "$S/skill.$id" ] && spec=$(cat "$S/skill.$id")
    name=""; magic=""; reps=""
    IFS='|' read -r name magic reps <<EOS
$spec
EOS
    fire=0
    if [ -n "$name" ]; then
      fire=1
      if [ -n "$magic" ] && ! grep -q "$magic" "$plugin/skills/$name/SKILL.md" 2>/dev/null; then fire=0; fi
      if [ -n "$reps" ]; then case " $reps " in *" $rep "*) ;; *) fire=0 ;; esac; fi
    fi
    if [ "$fire" = 1 ]; then
      echo '{"type":"assistant","message":{"id":"m1","content":[{"type":"tool_use","id":"tu1","name":"Skill","input":{"skill":"mogger:'"$name"'"}}],"usage":{"input_tokens":10,"output_tokens":5}}}'
      sleep 1
    fi
    printf 'ok' > "$S/tmp.txt"; emit_result success 0 "$S/tmp.txt"; exit 0 ;;
  proposer-*)
    f="$S/ans.$id"; [ -f "$f" ] || f="$S/ans.proposer-default"
    emit_result success 0 "$f"; exit 0 ;;
esac
f="$S/ans.$id.$tier"; [ -f "$f" ] || f="$S/ans.$id"; [ -f "$f" ] || { printf 'unknown' > "$S/tmp.txt"; f="$S/tmp.txt"; }
echo '{"type":"assistant","message":{"id":"m2","content":[{"type":"text","text":"working"}],"usage":{"input_tokens":10,"output_tokens":5}}}'
emit_result success 0 "$f"
EOF
chmod +x "$BIN/claude"
resetstub() { rm -f "$STUB"/*; }
setans() { printf '%s' "$2" > "$STUB/ans.$1"; }     # setans <id[.tier]> <text>
eng() {  # eng <args...>: run the engine inside the project sandbox
  OUT=$(cd "$PROJ" && bash "$EV" "$@" 2>&1); RC=$?
}
reset_project() { rm -rf "$PROJ/.claude"; }
pj() {  # pj <file> <python expr on d>  -> prints value
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$1" "$2"
}
LAST="$PROJ/.claude/state/evals/last.json"
setup_routing_stub() {
  resetstub
  setans t1 "alpha-7"; setans t2 "beta-8"; setans t3.haiku "wrong"; setans t3.sonnet "gamma-9"
}

echo "== portability lint"
for f in "$ROOT/scripts/mogger-eval.sh" "$ROOT/tests/evals.test.sh"; do
  body=$(grep -v '^[[:space:]]*#' "$f")
  hits=$(printf '%s\n' "$body" | grep -E 'mapfile|readarray|declare -A|grep -P|sed -i|head -n 0|readlink -f|date -d|stat -c|[$][{][a-z_]+,,|[[]A-Z[]]|[[]a-z[]]' | grep -v 'hits=' | head -1)
  [ -z "$hits" ] && ok "no bash4/GNU-only constructs: $(basename "$f")" || { bad "portability: $(basename "$f")"; printf '       %s\n' "$hits"; }
  bash -n "$f" 2>/dev/null && ok "bash -n $(basename "$f")" || bad "bash -n $(basename "$f")"
done
for f in "$ROOT"/scripts/eval/*.py; do python3 -m py_compile "$f" 2>/dev/null && ok "py_compile $(basename "$f")" || bad "py_compile $(basename "$f")"; done
find "$ROOT/scripts/eval" -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null

echo "== shipped data is valid"
OUT=$(cd "$PROJ" && MOGGER_EVAL_PLUGIN_ROOT="$ROOT" bash "$EV" validate 2>&1); RC=$?
eq "validate exits 0 on the real tasks" "$RC" "0"
has "validate: every gold passes, bad and blank fail" "OK: every task passes its gold answer"
has "validate: 5 agents covered" "5 agents"
for a in explorer bulk-reader fact-checker tester code-writer; do
  n=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["tasks"]))' "$ROOT/evals/tasks/$a.json")
  [ "$n" -ge 5 ] && ok "at least 5 tasks for $a ($n)" || bad "at least 5 tasks for $a ($n)"
done
cnt=0; miss=0
for d in "$ROOT"/skills/*/; do
  s=$(basename "$d"); cnt=$((cnt+1))
  python3 -c 'import json,sys; t=json.load(open(sys.argv[1]))["skills"].get(sys.argv[2]); sys.exit(0 if t and len(t["should"])>=6 and len(t["should_not"])>=6 else 1)' "$ROOT/evals/triggers.json" "$s" || { miss=$((miss+1)); printf '       no trigger prompts: %s\n' "$s"; }
done
eq "trigger prompts exist for all $cnt skills in skills/" "$miss" "0"
py_why=$(python3 -c 'import json,glob; print(sum(1 for f in glob.glob("'"$ROOT"'/evals/tasks/*.json") for t in json.load(open(f))["tasks"] if len(t.get("why_hard",""))<40))')
eq "every task has a substantive why_hard note" "$py_why" "0"
leak=$(grep -rl -E '"(gold|why_hard|grader)"' "$ROOT/evals/fixtures" 2>/dev/null | head -1)
eq "no answer keys inside fixtures" "$leak" ""

echo "== estimate (no model calls)"
reset_project; setup_routing_stub
eng estimate --suite routing --repeats 2
has "estimate: routing runs = 3 tasks x 4 candidates x 2" "runs: 24"
has "estimate: routing dollars (2 haiku 0.0375 + 2 sonnet 0.075 per task-repeat)" "estimated_usd: 1.35"
has "estimate labelled ESTIMATE" "ESTIMATE"
has "estimate lists models" "models: haiku,sonnet"
has "estimate gives minutes" "minutes:"
eng estimate --suite triggers --repeats 2
has "estimate: triggers runs = 2 skills x 12 x 2" "runs: 48"
has "estimate: triggers dollars" "estimated_usd: 1.66"
eng estimate --repeats 2
has "estimate: all = 72 runs" "runs: 72"
has "estimate: all dollars" "estimated_usd: 3.01"
eng estimate --suite routing --repeats 2 --no-effort-grid
has "estimate: no effort grid halves candidates" "runs: 12"
eng estimate --suite bogus
eq "estimate: bad suite is an error" "$RC" "2"
[ ! -f "$STUB/calls.log" ] && ok "estimate made no model calls" || bad "estimate made no model calls"
[ ! -e "$PROJ/.claude/state/evals/last.json" ] && ok "estimate wrote no results" || bad "estimate wrote no results"

echo "== consent gate"
reset_project; setup_routing_stub
eng run --suite routing --repeats 1
eq "run without consent or budget refuses (exit 2)" "$RC" "2"
has "refusal says why" "no consent and no --budget"
[ ! -f "$STUB/calls.log" ] && ok "refused run made no model calls" || bad "refused run made no model calls"
eng consent --budget abc
[ "$RC" -ne 0 ] && ok "consent rejects a non-number" || bad "consent rejects a non-number"
eng consent --budget 0
[ "$RC" -ne 0 ] && ok "consent rejects zero" || bad "consent rejects zero"
eng consent
[ "$RC" -ne 0 ] && ok "consent without args is an error" || bad "consent without args is an error"
eng consent --budget 5 --note "test grant"
eq "consent exits 0" "$RC" "0"
C="$PROJ/.claude/state/evals/consent.json"
eq "consent.json budget_usd" "$(pj "$C" 'd["budget_usd"]')" "5.0"
eq "consent.json has ts" "$(pj "$C" '"ts" in d and len(d["ts"])>10')" "True"
eq "consent.json note" "$(pj "$C" 'd["note"]')" "test grant"
eng status
has "status shows consent" "consent: budget \$5.00"
eng consent --revoke
eq "revoke exits 0" "$RC" "0"
[ ! -f "$C" ] && ok "revoke removes consent.json" || bad "revoke removes consent.json"
eng run --suite routing --repeats 1
eq "after revoke run refuses again" "$RC" "2"
eng consent --revoke
has "revoke twice is harmless" "no consent to remove"

echo "== run with consent: results, stats, recommendation"
reset_project; setup_routing_stub
eng consent --budget 50
eng run --suite routing --repeats 3 --jobs 4
eq "run exits 0" "$RC" "0"
[ -f "$LAST" ] && ok "last.json written" || bad "last.json written"
eq "last.json has ts" "$(pj "$LAST" '"ts" in d')" "True"
eq "last.json has fingerprint" "$(pj "$LAST" 'len(d["fingerprint"])>=12')" "True"
eq "last.json partial is false" "$(pj "$LAST" 'd["partial"]')" "False"
eq "last.json has routing suite with score/ci95/n/cost_usd/models" "$(pj "$LAST" 'all(k in d["suites"]["routing"] for k in ("score","ci95","n","cost_usd","models"))')" "True"
eq "routing models are haiku and sonnet" "$(pj "$LAST" 'd["suites"]["routing"]["models"]')" "['haiku', 'sonnet']"
eq "4 candidates for explorer (tier x effort)" "$(pj "$LAST" 'sorted(d["suites"]["routing"]["agents"]["explorer"]["candidates"])')" "['haiku@default', 'haiku@low', 'sonnet@default', 'sonnet@low']"
eq "haiku@low scored 6 of 9" "$(pj "$LAST" 'd["suites"]["routing"]["agents"]["explorer"]["candidates"]["haiku@low"]["k"]')" "6"
eq "sonnet@low scored 9 of 9" "$(pj "$LAST" 'd["suites"]["routing"]["agents"]["explorer"]["candidates"]["sonnet@low"]["k"]')" "9"
eq "CI is a two-number interval" "$(pj "$LAST" 'len(d["suites"]["routing"]["agents"]["explorer"]["candidates"]["haiku@low"]["ci95"])')" "2"
eq "run variance reported" "$(pj "$LAST" '"run_variance" in d["suites"]["routing"]["agents"]["explorer"]["candidates"]["haiku@low"]')" "True"
eq "cost is summed from the stub (0.01 x 36 trials)" "$(pj "$LAST" 'round(d["suites"]["routing"]["cost_usd"],2)')" "0.36"
has "9 runs: recommendation says gap is within noise" "within noise"
has "recommendation names the numbers" "explorer on Haiku scored 67% (CI 35-88)"
has "recommendation says no change" "no change is recommended"
eq "verdict is no_change_noise" "$(pj "$LAST" 'd["suites"]["routing"]["agents"]["explorer"]["verdict"]')" "no_change_noise"
[ -f "$PROJ/.claude/state/evals/report.html" ] && ok "report.html written" || bad "report.html written"
[ -f "$PROJ/.claude/state/evals/report.md" ] && ok "report.md written" || bad "report.md written"
eng run --suite routing --repeats 8 --jobs 4 --no-effort-grid
has "24 runs: real gap is called out" "consider Sonnet"
eq "verdict is consider_sonnet" "$(pj "$LAST" 'd["suites"]["routing"]["agents"]["explorer"]["verdict"]')" "consider_sonnet"
setans t3.haiku "gamma-9"
eng run --suite routing --repeats 4 --jobs 4 --no-effort-grid
has "no gap: keep Haiku" "keep Haiku"
eq "haiku 100 percent" "$(pj "$LAST" 'd["suites"]["routing"]["agents"]["explorer"]["candidates"]["haiku@low"]["score"]')" "1.0"
has "headroom warning at >= 95%" "Aim at cost, not quality"
eng report
has "report is plain words" "mogger eval results"
has "report says estimates" "ESTIMATES"

echo "== headless flags the engine passes"
# parallel jobs (--jobs 4) make the FIRST t1 line arbitrary (any tier, any effort); pick the haiku@low call
AL=$(grep '^t1|' "$STUB/args.log" | grep -e '--model haiku' | grep -e '--effort low' | head -1)
for f in "--output-format stream-json" "--verbose" "--model haiku" "--agent explorer" "--permission-mode dontAsk" "--max-turns" "--max-budget-usd" "--no-session-persistence" "--effort low" "--tools=Read,Grep" "--allowedTools=Read,Grep" "--setting-sources project" "--agents {"; do
  case "$AL" in *"$f"*) ok "routing call passes: $f";; *) bad "routing call passes: $f"; printf '       %s\n' "$AL";; esac
done
case "$AL" in *"Where is alpha?"*) ok "routing call passes the task prompt via -p";; *) bad "routing call passes the task prompt via -p";; esac
case "$AL" in *"log the savings"*) bad "savings-log section is stripped from the tested agent prompt";; *) ok "savings-log section is stripped from the tested agent prompt";; esac
case "$AL" in *"You find things."*) ok "agent body is the system prompt under test";; *) bad "agent body is the system prompt under test";; esac
DL=$(grep '^t1|' "$STUB/args.log" | grep -- '--model sonnet' | grep -- '--effort' | head -1)
[ -z "$DL" ] && ok "default effort passes no --effort flag for the sonnet@default candidate" || ok "sonnet@low passes --effort"
NL=$(grep '^t1|' "$STUB/args.log" | grep -v -- '--effort' | head -1)
[ -n "$NL" ] && ok "default-effort candidates omit --effort" || bad "default-effort candidates omit --effort"

echo "== budget hard-stop"
reset_project; setup_routing_stub; printf '0.30' > "$STUB/cost"
eng run --suite routing --repeats 3 --budget 1.0 --jobs 1 --no-effort-grid
eq "budget run exits 0 (partial is a result, not a crash)" "$RC" "0"
eq "partial flag true" "$(pj "$LAST" 'd["partial"]')" "True"
eq "stopped after 4 trials (0.30 each, budget 1.0)" "$(pj "$LAST" 'd["suites"]["routing"]["total_trials"]')" "4"
eq "spend is about 1.2, not the whole plan" "$(pj "$LAST" 'round(d["spent_usd"],2)')" "1.2"
eq "skipped runs recorded" "$(pj "$LAST" 'd["suites"]["routing"]["skipped_runs"]>0')" "True"
has "output says PARTIAL" "PARTIAL"
eq "warnings mention the budget stop" "$(pj "$LAST" 'any("PARTIAL" in w for w in d["warnings"])')" "True"
n_calls=$(wc -l < "$STUB/calls.log" | tr -d ' ')
eq "stub was called 4 times only" "$n_calls" "4"
eng run --suite routing --repeats 1 --budget 0.001 --jobs 1 --no-effort-grid
eq "tiny budget: at most one trial starts" "$(pj "$LAST" 'd["suites"]["routing"]["total_trials"]<=1')" "True"

echo "== split: stable, disjoint, seeded 70/30"
cat > "$SB/h_split.py" <<'EOF'
import sys
sys.path.insert(0, sys.argv[1] + "/scripts/eval")
import common
ids = [("task%03d" % i, "g") for i in range(100)]
a = common.split_ids(ids)
b = common.split_ids(list(reversed(ids)))
print("same", a == b)
tr = [i for i, s in a.items() if s == "train"]
ho = [i for i, s in a.items() if s == "heldout"]
print("counts", len(tr), len(ho))
print("disjoint", not (set(tr) & set(ho)), "cover", len(set(tr) | set(ho)) == 100)
c = common.split_ids(ids, seed="other-seed")
print("seed_matters", a != c)
small = common.split_ids([("a", "x"), ("b", "x")])
print("small", sorted(small.values()))
one = common.split_ids([("solo", "y")])
print("solo", one["solo"])
EOF
OUT=$(python3 "$SB/h_split.py" "$ROOT")
has "split is independent of input order (stable)" "same True"
has "split is 70/30" "counts 70 30"
has "train and held-out are disjoint and complete" "disjoint True cover True"
has "a different seed gives a different split" "seed_matters True"
has "two items: one on each side" "small ['heldout', 'train']"

echo "== CI math"
cat > "$SB/h_stats.py" <<'EOF'
import sys
sys.path.insert(0, sys.argv[1] + "/scripts/eval")
import common
lo, hi = common.wilson(9, 10); print("w9_10 %.3f %.3f" % (lo, hi))
lo, hi = common.wilson(0, 10); print("w0_10 %.3f %.3f" % (lo, hi))
lo, hi = common.wilson(10, 10); print("w10_10 %.3f %.3f" % (lo, hi))
print("w_empty", common.wilson(0, 0))
d, lo, hi = common.diff_ci(5, 10, 5, 10); print("d_equal %.3f %s" % (d, lo < 0 < hi))
d, lo, hi = common.diff_ci(0, 50, 50, 50); print("d_big %.2f %s" % (d, lo > 0))
print("sd %.4f" % common.sample_sd([1, 2, 3, 4]))
print("sd1", common.sample_sd([5]))
print("mean", common.mean([1, 2, 3]))
print("cost %.4f" % common.token_cost("haiku", 30000, 1500))
EOF
OUT=$(python3 "$SB/h_stats.py" "$ROOT")
has "Wilson 9/10" "w9_10 0.596 0.982"
has "Wilson 0/10 lower bound is 0" "w0_10 0.000 0.278"
has "Wilson 10/10 upper bound is 1" "w10_10 0.722 1.000"
has "Wilson with no trials is the whole range" "w_empty (0.0, 1.0)"
has "equal proportions: difference 0, CI spans 0" "d_equal 0.000 True"
has "0/50 vs 50/50: difference 1, CI above 0" "d_big 1.00 True"
has "sample sd" "sd 1.2910"
has "sd of one value is 0" "sd1 0.0"

echo "== grader twice"
reset_project; resetstub; setans f1 "x"
OUT=$(cd "$PROJ" && MOGGER_EVAL_DIR="$SB/ev_flaky" bash "$EV" run --suite routing --budget 5 --repeats 1 --jobs 1 --no-effort-grid 2>&1); RC=$?
eq "flaky-grader run exits 0" "$RC" "0"
eq "a grader that changes its mind is reported" "$(pj "$LAST" 'any("different verdicts on identical output for task f1" in w for w in d["warnings"])')" "True"

echo "== plumbing is not failure"
reset_project; resetstub
for t in p1 p5; do setans $t "fine"; done
printf 'timeout' > "$STUB/mode.p2"; printf 'empty' > "$STUB/mode.p3"; printf 'apierror' > "$STUB/mode.p4"
setans p2 fine
# p4 truncated is exercised through a second task file below; here p4 = api error
OUT=$(cd "$PROJ" && MOGGER_EVAL_DIR="$SB/ev_plumb" MOGGER_EVAL_TIMEOUT=2 bash "$EV" run --suite routing --budget 5 --repeats 1 --jobs 5 --no-effort-grid 2>&1); RC=$?
eq "plumbing run exits 0" "$RC" "0"
P='d["suites"]["routing"]["agents"]["explorer"]["candidates"]["haiku@low"]["plumbing"]'
eq "timeouts counted as plumbing" "$(pj "$LAST" "$P.get('timeout',0)")" "1"
eq "empty answers counted as plumbing" "$(pj "$LAST" "$P.get('empty',0)")" "1"
eq "API errors counted as plumbing" "$(pj "$LAST" "$P.get('api_error',0)")" "1"
eq "only the 2 healthy runs are scored" "$(pj "$LAST" 'd["suites"]["routing"]["agents"]["explorer"]["candidates"]["haiku@low"]["n"]')" "2"
eq "healthy runs pass (score not dragged down by plumbing)" "$(pj "$LAST" 'd["suites"]["routing"]["agents"]["explorer"]["candidates"]["haiku@low"]["score"]')" "1.0"
eq "warning explains unscored runs" "$(pj "$LAST" 'any("infrastructure problems" in w for w in d["warnings"])')" "True"
printf 'truncated' > "$STUB/mode.p4"; rm -f "$STUB/mode.p2" "$STUB/mode.p3"
OUT=$(cd "$PROJ" && MOGGER_EVAL_DIR="$SB/ev_plumb" MOGGER_EVAL_TIMEOUT=2 bash "$EV" run --suite routing --budget 5 --repeats 1 --jobs 5 --no-effort-grid 2>&1)
eq "cut-off answers (max turns) counted as plumbing" "$(pj "$LAST" "$P.get('truncated',0)")" "1"

echo "== fresh workspace isolation"
reset_project; resetstub
setans i1 "alpha-7"; setans i2 "beta-8"; setans i3 "gamma-9"
printf '%s\n' 'echo leftover > leak.txt' > "$STUB/side.i1.sh"
cat > "$STUB/side.i2.sh" <<'EOF'
{ echo "i2-sees-leak: $(ls leak.txt 2>/dev/null)"; echo "i2-commits: $(git log --oneline 2>/dev/null | wc -l | tr -d ' ')"; echo "i2-keyhits: $(grep -rlE 'alpha-7|beta-8|gamma-9' . 2>/dev/null | grep -v '^./.git' | wc -l | tr -d ' ')"; } >> "$STUB_DIR/iso.log"
EOF
cat > "$STUB/side.i3.sh" <<'EOF'
echo "i3-sees-leak: $(ls leak.txt 2>/dev/null)" >> "$STUB_DIR/iso.log"
EOF
OUT=$(cd "$PROJ" && MOGGER_EVAL_DIR="$SB/ev_iso" bash "$EV" run --suite routing --budget 5 --repeats 1 --jobs 1 --agents explorer --no-effort-grid 2>&1); RC=$?
IL=$(cat "$STUB/iso.log" 2>/dev/null)
case "$IL" in *"i2-sees-leak: "$'\n'*) ok "trial 2 does not see trial 1's leftover file";; *) bad "trial 2 does not see trial 1's leftover file"; printf '%s\n' "$IL";; esac
case "$IL" in *"i3-sees-leak: "*leak.txt*) bad "trial 3 sees no leftover";; *) ok "trial 3 sees no leftover";; esac
case "$IL" in *"i2-commits: 1"*) ok "workspace git history is one commit";; *) bad "workspace git history is one commit"; printf '%s\n' "$IL";; esac
case "$IL" in *"i2-keyhits: 0"*) ok "answer keys are not present in the workspace";; *) bad "answer keys are not present in the workspace"; printf '%s\n' "$IL";; esac
dirs=$(awk '{print $3}' "$STUB/calls.log" | sort -u | wc -l | tr -d ' ')
calls=$(wc -l < "$STUB/calls.log" | tr -d ' ')
eq "every trial ran in its own directory" "$dirs" "$calls"
gone=0; for d in $(awk '{print $3}' "$STUB/calls.log" | sort -u); do [ -e "$d" ] && gone=$((gone+1)); done
eq "trial workspaces are deleted afterwards" "$gone" "0"
[ ! -e "$SB/ev_iso/fixtures/mini/leak.txt" ] && ok "pristine fixture untouched by trials" || bad "pristine fixture untouched by trials"
sc=$(awk '{print $1}' "$STUB/calls.log" | sort -u | tr '\n' ' ')
case "$sc" in *"i1"*"i2"*"i3"*) ok "all three isolation tasks ran";; *) bad "all three isolation tasks ran ($sc)";; esac

echo "== triggers suite"
reset_project; resetstub
for i in 0 1 2 3 4 5; do printf 'alpha' > "$STUB/skill.trig.alpha.s$i"; printf 'beta' > "$STUB/skill.trig.beta.s$i"; done
printf 'alpha' > "$STUB/skill.trig.alpha.n0"
eng run --suite triggers --budget 20 --repeats 2 --jobs 6
eq "triggers run exits 0" "$RC" "0"
eq "triggers suite in last.json" "$(pj "$LAST" 'all(k in d["suites"]["triggers"] for k in ("score","ci95","n","cost_usd","models"))')" "True"
eq "trigger models default to sonnet" "$(pj "$LAST" 'd["suites"]["triggers"]["models"]')" "['sonnet']"
TL=$(grep '^trig.beta.s0|' "$STUB/args.log" | head -1)
for f in "--plugin-dir" "--allowedTools=Skill" "--permission-mode dontAsk" "--max-turns 3" "--output-format stream-json" "--model sonnet"; do
  case "$TL" in *"$f"*) ok "trigger call passes: $f";; *) bad "trigger call passes: $f"; printf '       %s\n' "$TL";; esac
done
eq "beta is perfect" "$(pj "$LAST" 'd["suites"]["triggers"]["skills"]["beta"]["score"]')" "1.0"
eq "alpha recall 100 percent" "$(pj "$LAST" 'd["suites"]["triggers"]["skills"]["alpha"]["recall"]')" "1.0"
eq "alpha false-trigger rate is 1 of 6" "$(pj "$LAST" 'round(d["suites"]["triggers"]["skills"]["alpha"]["false_rate"],3)')" "0.167"
eq "alpha accuracy 11 of 12" "$(pj "$LAST" 'round(d["suites"]["triggers"]["skills"]["alpha"]["score"],3)')" "0.917"
eq "24 prompts x 2 repeats scored" "$(pj "$LAST" 'd["suites"]["triggers"]["n"]')" "48"
eq "train and held-out both reported" "$(pj "$LAST" 'd["suites"]["triggers"]["skills"]["alpha"]["train"]["n"]+d["suites"]["triggers"]["skills"]["alpha"]["heldout"]["n"]')" "24"
has "triggers headroom warning" "Aim at cost, not quality"
# the Skill observable: the stub emits a tool_use named Skill; without it nothing triggers
resetstub
eng run --suite triggers --budget 20 --repeats 1 --jobs 6 --skills beta
eq "no Skill tool_use event = not triggered (recall 0)" "$(pj "$LAST" 'd["suites"]["triggers"]["skills"]["beta"]["recall"]')" "0.0"
eq "not triggering on should_not prompts counts as right" "$(pj "$LAST" 'd["suites"]["triggers"]["skills"]["beta"]["false_rate"]')" "0.0"

echo "== fingerprint change detection"
reset_project; setup_routing_stub
eng status
has "status before any run" "last run: none yet"
eng consent --budget 50
eng run --suite routing --repeats 1 --no-effort-grid
eng status
has "status shows last run age" "last run:"
has "fingerprint unchanged right after a run" "fingerprint: unchanged since the last run"
has "status shows not running" "running: no"
printf '\nExtra rule.\n' >> "$PLUG/agents/explorer.md"
eng status
has "editing an agent changes the fingerprint" "CHANGED since the last run"
eng run --suite routing --repeats 1 --no-effort-grid
eng status
has "fingerprint unchanged after re-run" "unchanged since the last run"
printf 'More body text.\n' >> "$PLUG/skills/alpha/SKILL.md"
eng status
has "a skill BODY edit does not change the fingerprint" "unchanged since the last run"
sed 's/^description: Alpha thing\./description: Alpha thing, edited./' "$PLUG/skills/alpha/SKILL.md" > "$SB/tmp.md" && mv "$SB/tmp.md" "$PLUG/skills/alpha/SKILL.md"
eng status
has "a skill description edit changes the fingerprint" "CHANGED since the last run"
sed 's/^description: Alpha thing, edited\./description: Alpha thing./' "$PLUG/skills/alpha/SKILL.md" > "$SB/tmp.md" && mv "$SB/tmp.md" "$PLUG/skills/alpha/SKILL.md"

echo "== report page is static and offline"
H="$PROJ/.claude/state/evals/report.html"; M="$PROJ/.claude/state/evals/report.md"
[ -f "$H" ] && ok "report.html exists" || bad "report.html exists"
if grep -qiE 'https?://' "$H" "$M"; then bad "report has no external URLs"; else ok "report has no external URLs"; fi
if grep -qiE '<script|<link|src=|@import|url\(' "$H"; then bad "report loads nothing (no script/link/src/import/url)"; else ok "report loads nothing (no script/link/src/import/url)"; fi
grep -q '<!doctype html>' "$H" && ok "report.html is a full page" || bad "report.html is a full page"
grep -q 'name="viewport"' "$H" && ok "report.html has a viewport meta (phone width)" || bad "report.html has a viewport meta"
grep -q 'estimates' "$H" && ok "report.html labels dollars as estimates" || bad "report.html labels dollars as estimates"

echo "== background mode"
reset_project; setup_routing_stub
eng run --background --suite triggers --repeats 1
eq "background without consent refuses" "$RC" "2"
[ ! -e "$PROJ/.claude/state/evals/running.pid" ] && ok "refused background run left no pid file" || bad "refused background run left no pid file"
resetstub; printf '1' > "$STUB/delay"
eng consent --budget 20
eng run --background --suite triggers --repeats 1 --skills alpha --jobs 2
eq "background start exits 0 at once" "$RC" "0"
has "background start prints the log path" "run.log"
PF="$PROJ/.claude/state/evals/running.pid"
[ -s "$PF" ] && ok "running.pid written" || bad "running.pid written"
pid=$(tr -dc '0-9' < "$PF" 2>/dev/null)
kill -0 "$pid" 2>/dev/null && ok "pid in running.pid is alive" || bad "pid in running.pid is alive"
eng status
has "status shows the run in progress" "running: yes"
eng run --suite triggers --repeats 1
eq "a second run is refused while one is going" "$RC" "2"
n=0; while [ -e "$PF" ] && [ "$n" -lt 150 ]; do sleep 0.2; n=$((n+1)); done
[ ! -e "$PF" ] && ok "running.pid removed when the run ends" || bad "running.pid removed when the run ends"
[ -f "$LAST" ] && ok "background run wrote last.json" || bad "background run wrote last.json"
[ -s "$PROJ/.claude/state/evals/run.log" ] && ok "run.log has output" || bad "run.log has output"
grep -q 'Report page' "$PROJ/.claude/state/evals/run.log" && ok "run.log shows the finished report" || bad "run.log shows the finished report"

echo "== hillclimb: helpers for train/held-out ids"
cat > "$SB/h_ids.py" <<'EOF'
import sys
sys.path.insert(0, sys.argv[1] + "/scripts/eval")
import common, suites
skills = common.load_skills()
items = suites.load_trigger_items(skills, ["alpha"])
kind = sys.argv[2]
sel = [it for it in items if it["split"] == kind[:kind.index(":")] and it["cls"] == kind[kind.index(":") + 1:]]
print(" ".join(it["id"] for it in sel))
EOF
ids() { python3 "$SB/h_ids.py" "$ROOT" "$1"; }    # ids train:should | heldout:should_not ...
TR_S=$(ids train:should); HO_S=$(ids heldout:should); TR_N=$(ids train:should_not); HO_N=$(ids heldout:should_not)
eq "alpha has 4 train + 2 held-out should prompts" "$(echo $TR_S | wc -w | tr -d ' ')/$(echo $HO_S | wc -w | tr -d ' ')" "4/2"
eq "alpha has 4 train + 2 held-out should_not prompts" "$(echo $TR_N | wc -w | tr -d ' ')/$(echo $HO_N | wc -w | tr -d ' ')" "4/2"
setmagic() {  # every should prompt fires only when the description contains the word MAGIC
  local i; for i in 0 1 2 3 4 5; do printf 'alpha|MAGIC' > "$STUB/skill.trig.alpha.s$i"; done
}
DESC_GOOD='Use whenever the user needs help with MAGIC situations of the alpha kind, not for unrelated requests.'

echo "== hillclimb: a real improvement is kept"
reset_project; resetstub; setmagic
printf '{"description": "%s"}' "$DESC_GOOD" > "$STUB/ans.proposer-1"
cp "$PLUG/skills/alpha/SKILL.md" "$SB/alpha.before"
eng consent --budget 50
eng hillclimb --skill alpha --rounds 1 --repeats 3 --jobs 6
eq "hillclimb exits 0" "$RC" "0"
has "round 1 kept" "Round 1: kept"
PROP=$(ls "$PROJ/.claude/state/evals/proposals/"alpha-*.json 2>/dev/null | head -1)
[ -n "$PROP" ] && ok "proposal written under .claude/state/evals/proposals/" || bad "proposal written"
eq "proposal recommends applying" "$(pj "$PROP" 'd["recommend_apply"]')" "True"
eq "proposal holds the new description" "$(pj "$PROP" 'd["final_description"]')" "$DESC_GOOD"
eq "proposal records the old description" "$(pj "$PROP" 'd["base_description"]')" "Alpha thing."
eq "held-out gain reported with a CI" "$(pj "$PROP" 'len(d["heldout_gain"]["ci95_points"])')" "2"
eq "held-out gain is above zero" "$(pj "$PROP" 'd["heldout_gain"]["ci95_points"][0]>0')" "True"
eq "baseline train accuracy 50 percent (should_not right, should missed)" "$(pj "$PROP" 'd["baseline"]["train"]["acc"]')" "0.5"
eq "final train accuracy 100 percent" "$(pj "$PROP" 'd["final"]["train"]["acc"]')" "1.0"
eq "plugin SKILL.md not edited by hillclimb" "$(cmp -s "$PLUG/skills/alpha/SKILL.md" "$SB/alpha.before" && echo same)" "same"
[ -f "${PROP%.json}.diff" ] && ok "a .diff of the proposal is written" || bad "a .diff of the proposal is written"
PID_=$(basename "$PROP" .json)

echo "== held-out prompts never reach the proposer"
OUT=$(python3 - "$ROOT" "$PLUG" "$STUB" <<'EOF'
import sys, os
sys.path.insert(0, sys.argv[1] + "/scripts/eval")
os.environ["MOGGER_EVAL_PLUGIN_ROOT"] = sys.argv[2]
import common, suites
items = suites.load_trigger_items(common.load_skills(), ["alpha"])
held = [it["prompt"] for it in items if it["split"] == "heldout"]
train = [it["prompt"] for it in items if it["split"] == "train"]
p = open(sys.argv[3] + "/proposer_prompt.1").read()
print("held_leaked", sum(1 for h in held if h in p))
print("train_shown", sum(1 for t in train if t in p))
EOF
)
has "no held-out prompt text in the proposer prompt" "held_leaked 0"
has "train prompts are shown to the proposer (so the check is meaningful)" "train_shown 8"
cat > "$SB/h_guard.py" <<'EOF'
import sys, os
sys.path.insert(0, sys.argv[1] + "/scripts/eval")
import hillclimb as hc
inp = ["Please help me with the alpha situation number 3 right now"]
try:
    hc.assert_no_leak("Context: Please help me with the alpha situation number 3 right now, ok", inp)
    print("assert_no_leak: no raise")
except AssertionError:
    print("assert_no_leak: raised")
hc.assert_no_leak("Use for alpha kind of work", inp); print("clean text passes")
ok, why = hc.check_patch("Use for alpha. Please help me with the alpha situation number 3 right now.", "Use for alpha.", inp)
print("patch_copy", ok, why[:22])
ok, why = hc.check_patch("Use for alpha work. Note-help me with the al", "Use for alpha.", inp)
print("under_20", ok)
ok, why = hc.check_patch("Use for alpha.", "Use for alpha.", inp); print("nochange", ok, why)
ok, why = hc.check_patch("", "x", inp); print("empty", ok)
ok, why = hc.check_patch("line one\nline two", "x", inp); print("multiline", ok)
ok, why = hc.check_patch("Please help me with the alpha situation number 3 right now", "Please help me with the alpha situation number 3 right now, and more", inp)
print("kept_old_text_ok", ok)
EOF
OUT=$(python3 "$SB/h_guard.py" "$ROOT")
has "guard: leaking held-out text into a prompt raises" "assert_no_leak: raised"
has "guard: clean text passes" "clean text passes"
has "guard: a patch copying 20+ chars of a task input is refused" "patch_copy False patch copies task text"
has "guard: 19 copied chars are allowed" "under_20 True"
has "guard: no-change patch refused" "nochange False no change"
has "guard: empty description refused" "empty False"
has "guard: multi-line description refused" "multiline False"
has "guard: text already in the old description is not counted as copied" "kept_old_text_ok True"

echo "== no failure text in the patch (end to end)"
reset_project; resetstub; setmagic
TR0=${TR_S%% *}; IDX=${TR0##*.s}
SHOULD0=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["skills"]["alpha"]["should"][int(sys.argv[2])])' "$PLUG/evals/triggers.json" "$IDX")
python3 -c 'import json,sys; print(json.dumps({"description": "MAGIC helper. Example: " + sys.argv[1]}))' "$SHOULD0" > "$STUB/ans.proposer-1"
eng consent --budget 50
eng hillclimb --skill alpha --rounds 1 --repeats 2 --jobs 6
has "copying a task prompt into the description is refused" "patch copies task text"
PROP2=$(ls -t "$PROJ/.claude/state/evals/proposals/"alpha-*.json | head -1)
eq "the copying patch is not part of any proposal" "$(pj "$PROP2" 'd["changed"]')" "False"
eq "round marked rejected" "$(pj "$PROP2" 'd["rounds"][0]["decision"]')" "rejected"
eq "proposal does not recommend applying" "$(pj "$PROP2" 'd["recommend_apply"]')" "False"

echo "== overfitting: train up, held-out flat => reverted"
reset_project; resetstub
for id in $TR_S; do printf 'alpha|MAGIC' > "$STUB/skill.$id"; done
for id in $HO_S; do printf 'alpha|NEVERMATCHES' > "$STUB/skill.$id"; done
printf '{"description": "%s"}' "$DESC_GOOD" > "$STUB/ans.proposer-1"
eng consent --budget 50
eng hillclimb --skill alpha --rounds 1 --repeats 3 --jobs 6
has "overfit patch is reverted" "Round 1: reverted"
has "reason says overfitting" "overfitting"
PROP3=$(ls -t "$PROJ/.claude/state/evals/proposals/"alpha-*.json | head -1)
eq "overfit proposal left the description alone" "$(pj "$PROP3" 'd["changed"]')" "False"
eq "recorded train after > before" "$(pj "$PROP3" 'd["rounds"][0]["train"]["after"]>d["rounds"][0]["train"]["before"]')" "True"
eq "recorded held-out flat" "$(pj "$PROP3" 'd["rounds"][0]["heldout"]["after"]==d["rounds"][0]["heldout"]["before"]')" "True"

echo "== stall reflection: no edit, failures bucketed by cause"
reset_project; resetstub; setmagic
NEARMISS=${TR_N%% *}
printf 'alpha' > "$STUB/skill.$NEARMISS"          # a train near-miss that always fires
printf '{"description": "%s"}' "$DESC_GOOD" > "$STUB/ans.proposer-1"
printf '{"description": "%s"}' "$DESC_GOOD" > "$STUB/ans.proposer-2"       # no change -> guard
printf '{"description": "%s MAGIC again."}' "$DESC_GOOD" > "$STUB/ans.proposer-3"  # tiny rewording -> no gain
eng consent --budget 50
eng hillclimb --skill alpha --rounds 5 --repeats 2 --jobs 6
has "round 1 kept" "Round 1: kept"
has "round 2 refused as no change" "Round 2 rejected before testing: no change"
has "round 3 reverted (no gain)" "Round 3: reverted"
has "after two stalled rounds: reflection" "stall reflection, no edit"
has "failures bucketed by cause" "fires on a near-miss it should ignore"
PROP4=$(ls -t "$PROJ/.claude/state/evals/proposals/"alpha-*.json | head -1)
eq "reflection round made no edit" "$(pj "$PROP4" 'd["rounds"][-1]["decision"]')" "no edit"
eq "final description is the kept one, not a reflection edit" "$(pj "$PROP4" 'd["final_description"]')" "$DESC_GOOD"
eq "exactly 4 rounds logged (1 kept, 2 stalled, 1 reflection)" "$(pj "$PROP4" 'len(d["rounds"])')" "4"

echo "== noise check and headroom before hillclimbing"
reset_project; resetstub
for i in 0 1 2 3 4 5; do printf 'alpha||1' > "$STUB/skill.trig.alpha.s$i"; done   # fires on repeat 1 only
printf '{"description": "%s"}' "$DESC_GOOD" > "$STUB/ans.proposer-1"
eng consent --budget 50
eng hillclimb --skill alpha --rounds 2 --repeats 3 --jobs 6
has "noisy eval: says the noise is larger than the smallest gain" "Noise (about"
has "noisy eval: suggests more repeats" "--repeats"
[ ! -f "$STUB/proposer_prompt.1" ] && ok "noisy eval: no proposer call was spent" || bad "noisy eval: no proposer call was spent"
reset_project; resetstub
for i in 0 1 2 3 4 5; do printf 'alpha' > "$STUB/skill.trig.alpha.s$i"; done         # already perfect
eng consent --budget 50
eng hillclimb --skill alpha --rounds 2 --repeats 2 --jobs 6
has "saturated eval: headroom warning" "Aim at cost, not quality"
[ ! -f "$STUB/proposer_prompt.1" ] && ok "saturated eval: no proposer call was spent" || bad "saturated eval: no proposer call was spent"
eng hillclimb --skill nosuchskill
[ "$RC" -ne 0 ] && ok "unknown skill is an error" || bad "unknown skill is an error"
reset_project
eng hillclimb --skill alpha
eq "hillclimb without consent refuses" "$RC" "2"

echo "== apply"
reset_project; resetstub; setmagic
printf '{"description": "%s"}' "$DESC_GOOD" > "$STUB/ans.proposer-1"
eng consent --budget 50
eng hillclimb --skill alpha --rounds 1 --repeats 3 --jobs 6
PROP5=$(ls -t "$PROJ/.claude/state/evals/proposals/"alpha-*.json | head -1); AID=$(basename "$PROP5" .json)
cp "$PLUG/skills/alpha/SKILL.md" "$SB/alpha.before"
eng apply "$AID"
eq "apply without --yes exits 0" "$RC" "0"
has "apply prints the diff (added line)" "+description: $DESC_GOOD"
has "apply prints the diff (removed line)" "-description: Alpha thing."
has "apply says nothing was written" "Nothing written"
[ ! -e "$PROJ/.claude/skills/alpha/SKILL.md" ] && ok "no file written without --yes" || bad "no file written without --yes"
eng apply "$AID" --yes --target "$PLUG/skills/alpha/SKILL.md"
eq "apply --yes to the plugin dir is refused" "$RC" "2"
eq "plugin file unchanged after refused apply" "$(cmp -s "$PLUG/skills/alpha/SKILL.md" "$SB/alpha.before" && echo same)" "same"
eng apply "$AID" --yes --target "$SB/outside.md"
eq "apply --yes outside .claude/ is refused" "$RC" "2"
[ ! -e "$SB/outside.md" ] && ok "nothing written outside .claude/" || bad "nothing written outside .claude/"
eng apply "$AID" --yes --target "$PROJ/../escape.md"
eq "apply with a .. escape is refused" "$RC" "2"
mkdir -p "$PROJ/.claude"; ln -s "$SB" "$PROJ/.claude/linkout"
eng apply "$AID" --yes --target "$PROJ/.claude/linkout/viasym.md"
eq "apply through a symlink out of .claude/ is refused" "$RC" "2"
[ ! -e "$SB/viasym.md" ] && ok "nothing written through the symlink" || bad "nothing written through the symlink"
rm -f "$PROJ/.claude/linkout"
eng apply "$AID" --yes
eq "apply --yes to the default override exits 0" "$RC" "0"
OV="$PROJ/.claude/skills/alpha/SKILL.md"
[ -f "$OV" ] && ok "project-level override written under .claude/skills/" || bad "project-level override written"
grep -q "^description: $DESC_GOOD" "$OV" && ok "override carries the new description" || bad "override carries the new description"
grep -q 'Body one' "$OV" && ok "override keeps the skill body" || bad "override keeps the skill body"
eq "plugin file still unchanged after a real apply" "$(cmp -s "$PLUG/skills/alpha/SKILL.md" "$SB/alpha.before" && echo same)" "same"
eng apply nosuchid
[ "$RC" -ne 0 ] && ok "unknown proposal id is an error" || bad "unknown proposal id is an error"
# a proposal the eval does not recommend needs --force
python3 - "$PROP5" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1])); d["recommend_apply"] = False; d["verdict"] = "within noise"
json.dump(d, open(sys.argv[1].replace(".json", "-weak.json"), "w"))
EOF
rm -f "$OV"
eng apply "${AID}-weak" --yes
eq "a within-noise proposal is not written without --force" "$RC" "2"
[ ! -e "$OV" ] && ok "weak proposal wrote nothing" || bad "weak proposal wrote nothing"
eng apply "${AID}-weak" --yes --force
eq "--force writes it (still only under .claude/)" "$RC" "0"

echo "== misc"
eng
eq "no command prints usage and exits 2" "$RC" "2"
eng --help
has "help shows usage" "USAGE"
eng bogus
[ "$RC" -ne 0 ] && ok "unknown command is an error" || bad "unknown command is an error"
OUT=$(cd "$PROJ" && bash "$EV" run --repeats 0 --budget 1 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok "repeats 0 is rejected" || bad "repeats 0 is rejected"
[ ! -e "$PLUG/evals/tasks/../fixtures/mini/.git" ] && ok "fixtures have no git history" || bad "fixtures have no git history"
gitfx=$(find "$ROOT/evals/fixtures" -name .git 2>/dev/null | head -1)
eq "shipped fixtures contain no .git directory" "$gitfx" ""

echo
echo "evals.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
