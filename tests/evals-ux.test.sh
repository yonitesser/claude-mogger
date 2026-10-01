#!/usr/bin/env bash
# Tests for the evals UX: free static check, session-start nudge, consent-gated auto-run.
# Run: bash tests/evals-ux.test.sh
# Uses a STUB engine (MOGGER_EVAL_BIN) that records calls. No API calls, no cost.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
H="$ROOT/hooks/scripts"
STATIC="$ROOT/scripts/checks/evals-static.sh"
NUDGE="$H/evals-nudge.sh"
PASS=0; FAIL=0

SANDBOX=$(mktemp -d 2>/dev/null || mktemp -d -t mogger)
BGPIDS=""
cleanup() {
  for p in $BGPIDS; do kill "$p" 2>/dev/null; done
  rm -rf "$SANDBOX"
}
trap cleanup EXIT
cd "$SANDBOX"

ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

expect() {  # expect <want-string> <got-string> <desc>
  if [ "$1" = "$2" ]; then ok "$3"; else bad "$3"; printf '       want: [%s]\n       got:  [%s]\n' "$1" "$2"; fi
}
expect_has() {  # expect_has <text> <fixed-substring> <desc>
  if printf '%s\n' "$1" | grep -qF -- "$2"; then ok "$3"; else bad "$3"; printf '       missing: [%s]\n       in: [%s]\n' "$2" "$1"; fi
}
expect_not() {  # expect_not <text> <fixed-substring> <desc>
  if printf '%s\n' "$1" | grep -qF -- "$2"; then bad "$3"; printf '       unexpected: [%s]\n' "$2"; else ok "$3"; fi
}
expect_empty() { if [ -z "$1" ]; then ok "$2"; else bad "$2"; printf '       got: [%s]\n' "$1"; fi; }

# ---------------------------------------------------------------- stub engine
STUB="$SANDBOX/stub-eval.sh"
LOG="$SANDBOX/calls.log"
cat > "$STUB" <<'STUBEOF'
#!/usr/bin/env bash
# records every call; prints a fixed estimate
echo "$*" >> "${STUB_LOG:-/dev/null}"
case "${1:-}" in
  estimate)
    if [ -n "${STUB_HANG:-}" ]; then sleep 30; fi
    if [ -n "${STUB_NONUM:-}" ]; then echo "Estimate not available."; exit 0; fi
    echo "Estimated cost: about \$${STUB_EST:-1.50} for one run."
    ;;
esac
exit 0
STUBEOF
chmod +x "$STUB"

export MOGGER_EVAL_BIN="$STUB"
export STUB_LOG="$LOG"
export CLAUDE_PLUGIN_ROOT="$SANDBOX/plug"
mkdir -p "$CLAUDE_PLUGIN_ROOT/agents" "$CLAUDE_PLUGIN_ROOT/skills/s1"
printf -- '---\nname: a1\ndescription: Use when testing.\nmodel: haiku\n---\nbody\n' > "$CLAUDE_PLUGIN_ROOT/agents/a1.md"
printf -- '---\nname: s1\ndescription: Use when testing skills.\n---\nbody\n' > "$CLAUDE_PLUGIN_ROOT/skills/s1/SKILL.md"

NP=0
fresh() {  # new empty project; resets log and env knobs
  NP=$((NP+1)); P="$SANDBOX/proj$NP"; D="$P/.claude/state/evals"
  mkdir -p "$P"; : > "$LOG"
  export CLAUDE_PROJECT_DIR="$P"
  unset MOGGER_EVALS MOGGER_NUDGE_DAYS MOGGER_EVAL_MAX_AGE_DAYS STUB_EST STUB_HANG STUB_NONUM
  export MOGGER_EVAL_BIN="$STUB"
}
nudge() { bash "$NUDGE" 2>/dev/null; }
runs()  { grep -c '^run' "$LOG" 2>/dev/null || true; }
ests()  { grep -c '^estimate' "$LOG" 2>/dev/null || true; }
consent() {  # consent <budget> [spent]
  mkdir -p "$D"
  printf '{"budget_usd": %s, "spent_usd": %s}\n' "$1" "${2:-0}" > "$D/consent.json"
}
wait_runs() {  # wait up to 5s for >= N run calls, then settle
  local want="$1" i=0
  while [ "$i" -lt 50 ]; do
    [ "$(runs)" -ge "$want" ] && break
    sleep 0.1; i=$((i+1))
  done
  sleep 0.4
}
old() { touch -t "$1" "$2"; }   # old <YYYYMMDDhhmm> <file>
now_s() { date +%s; }
ALLOUT="$SANDBOX/allout.txt"; : > "$ALLOUT"

# shellcheck disable=SC1090
source "$NUDGE"
FP=$(CLAUDE_PROJECT_DIR="$SANDBOX/none" evals_fingerprint)
[ -n "$FP" ] && ok "fingerprint is non-empty" || bad "fingerprint is non-empty"

echo "== nudge: show once"
fresh
out=$(nudge); printf '%s\n' "$out" >> "$ALLOUT"
expect_has "$out" "Mogger evals" "first session shows the nudge"
expect_has "$out" '$1.50' "nudge shows the estimate from the engine"
expect_has "$out" "cost money" "nudge says it costs money"
expect_has "$out" "Nothing runs unless you say yes" "nudge says nothing runs without yes"
expect_has "$out" "MOGGER_EVALS=off" "nudge names the off switch"
expect_has "$out" "evals-static.sh" "nudge names the free check"
expect_has "$(cat "$D/nudge.json")" '"shown"' "nudge.json records shown"
expect "0" "$(runs)" "nudge never starts a run"
out2=$(nudge)
expect_empty "$out2" "second session is quiet"
expect "1" "$(ests)" "second session did not call the engine again"

echo "== nudge: days window"
fresh; nudge >/dev/null
printf '{"state":"shown","shown_at":%s}\n' "$(( $(now_s) - 20*86400 ))" > "$D/nudge.json"
expect_has "$(nudge)" "Mogger evals" "shown again after 20 days (default 14)"
printf '{"state":"shown","shown_at":%s}\n' "$(( $(now_s) - 3*86400 ))" > "$D/nudge.json"
expect_empty "$(nudge)" "quiet after 3 days"
export MOGGER_NUDGE_DAYS=2
expect_has "$(nudge)" "Mogger evals" "MOGGER_NUDGE_DAYS=2 shows after 3 days"
export MOGGER_NUDGE_DAYS=abc
printf '{"state":"shown","shown_at":%s}\n' "$(( $(now_s) - 3*86400 ))" > "$D/nudge.json"
expect_empty "$(nudge)" "bad MOGGER_NUDGE_DAYS falls back to 14"

echo "== nudge: dismissed and consented stay quiet"
fresh; mkdir -p "$D"
printf '{"state":"dismissed","shown_at":%s}\n' "$(( $(now_s) - 90*86400 ))" > "$D/nudge.json"
expect_empty "$(nudge)" "dismissed stays quiet even after 90 days"
expect "0" "$(ests)" "dismissed does not call the engine"
fresh; mkdir -p "$D"
printf '{"state":"consented","shown_at":%s}\n' "$(( $(now_s) - 90*86400 ))" > "$D/nudge.json"
expect_empty "$(nudge)" "state consented stays quiet after 90 days"
fresh; consent 5
printf '%s' "$FP" > /dev/null
o=$(nudge); wait_runs 1
expect_not "$o" "Mogger evals" "consent.json present: no nudge text"
expect_has "$(cat "$D/nudge.json")" '"consented"' "consent.json marks nudge.json consented"

echo "== nudge: estimate handling"
fresh; export STUB_NONUM=1
out=$(nudge)
expect_has "$out" "mogger-eval.sh estimate" "no number: points at the estimate command"
expect_not "$out" '$1.50' "no number: does not invent one"
fresh; export STUB_HANG=1
t0=$(now_s); out=$(nudge); t1=$(now_s)
expect_has "$out" "Mogger evals" "hanging estimate: nudge still shown"
[ $((t1 - t0)) -le 4 ] && ok "hanging estimate: returned within 4s" || bad "hanging estimate: took $((t1 - t0))s"

echo "== auto-run: consented"
fresh; consent 5
out=$(nudge); wait_runs 1; ALLRUN=$(cat "$LOG")
printf '%s\n' "$out" >> "$ALLOUT"
expect "1" "$(runs)" "consented + no last.json: exactly one run launched"
expect_has "$ALLRUN" "run --background" "run uses --background"
expect_has "$ALLRUN" "--budget 5.00" "run passes the remaining cap"
expect_has "$out" "started a background run" "session text says a run started"
expect_has "$out" '$1.50' "session text shows the estimate"
expect_has "$(cat "$D/auto.json")" "$FP" "auto.json records the fingerprint"
nudge >/dev/null; wait_runs 2
expect "1" "$(runs)" "second session within 12h: no second run"
old 202001010000 "$D/auto.json"
export MOGGER_EVAL_MAX_AGE_DAYS=99999
nudge >/dev/null; wait_runs 2
unset MOGGER_EVAL_MAX_AGE_DAYS
expect "1" "$(runs)" "auto.json old but same fingerprint: no run (nothing changed)"
printf 'changed\n' >> "$CLAUDE_PLUGIN_ROOT/agents/a1.md"
nudge >/dev/null; wait_runs 2
expect "2" "$(runs)" "agent file changed and 12h passed: one more run"
printf -- '---\nname: a1\ndescription: Use when testing.\nmodel: haiku\n---\nbody\n' > "$CLAUDE_PLUGIN_ROOT/agents/a1.md"

fresh; consent 5
FP2=$(evals_fingerprint)
printf '{"fingerprint":"%s","summary":"4 of 5 Haiku agents match Sonnet"}\n' "$FP2" > "$D/last.json"
: > "$D/report.md"; : > "$D/seen"; old 202001010000 "$D/seen"
out=$(nudge); wait_runs 1
expect "0" "$(runs)" "fingerprint equals last.json: no run"
expect_has "$out" "Evals: 4 of 5 Haiku agents match Sonnet. See .claude/state/evals/report.md" "one-line last results"
printf '%s\n' "$out" >> "$ALLOUT"
out=$(nudge)
expect_empty "$out" "results line shown once per new report"
: > "$D/report.md"; old 202001010000 "$D/seen"
expect_has "$(nudge)" "4 of 5 Haiku agents" "newer report shows the line again"
rm -f "$D/seen"; printf '{"fingerprint":"%s"}\n' "$FP2" > "$D/last.json"
expect_has "$(nudge)" "Evals: new results." "report without summary: generic line"

fresh; consent 5
printf '{"fingerprint":"%s"}\n' "$FP2" > "$D/last.json"; old 202001010000 "$D/last.json"
nudge >/dev/null; wait_runs 1
expect "1" "$(runs)" "last run older than 30 days: run launched"
fresh; consent 5
printf '{"fingerprint":"%s"}\n' "$FP2" > "$D/last.json"; old 202001010000 "$D/last.json"
export MOGGER_EVAL_MAX_AGE_DAYS=99999
nudge >/dev/null; wait_runs 1
expect "0" "$(runs)" "MOGGER_EVAL_MAX_AGE_DAYS raises the age limit"
unset MOGGER_EVAL_MAX_AGE_DAYS

echo "== auto-run: pid guard"
fresh; consent 5
sleep 60 & LIVE=$!; BGPIDS="$BGPIDS $LIVE"
printf '%s\n' "$LIVE" > "$D/running.pid"
out=$(nudge); wait_runs 1
expect "0" "$(runs)" "live running.pid: no run"
expect_empty "$out" "live running.pid: quiet"
expect "0" "$(ests)" "live running.pid: engine not even asked for an estimate"
kill "$LIVE" 2>/dev/null; wait "$LIVE" 2>/dev/null
nudge >/dev/null; wait_runs 1
expect "1" "$(runs)" "dead pid in running.pid: run launched"
fresh; consent 5; mkdir -p "$D"; printf 'not-a-pid\n' > "$D/running.pid"
nudge >/dev/null; wait_runs 1
expect "1" "$(runs)" "garbage running.pid: run launched"

echo "== auto-run: cap"
fresh; consent 5; export STUB_EST=9
out=$(nudge); wait_runs 1
printf '%s\n' "$out" >> "$ALLOUT"
expect "0" "$(runs)" "estimate above cap: no run"
expect_has "$out" "cap too low" "estimate above cap: says cap too low"
expect_has "$out" '$9' "estimate above cap: says how much is needed"
expect_empty "$(nudge)" "cap-too-low note not repeated inside the window"
expect "0" "$(runs)" "still no run"
fresh; consent 5 4.5; export STUB_EST=1.50
out=$(nudge); wait_runs 1
expect "0" "$(runs)" "spent counts against the cap: no run"
expect_has "$out" '$0.50' "shows what is left in the cap"
fresh; consent 5 3.5; export STUB_EST=1.50
nudge >/dev/null; wait_runs 1
expect "1" "$(runs)" "estimate equal to remaining cap: run launched"
expect_has "$(cat "$LOG")" "--budget 1.50" "run gets the remaining cap, not the full cap"
fresh; consent 5; export STUB_NONUM=1
nudge >/dev/null; wait_runs 1
expect "0" "$(runs)" "no usable estimate: no paid run"
fresh; mkdir -p "$D"; printf '{"budget_usd": 0}\n' > "$D/consent.json"
out=$(nudge); wait_runs 1
expect "0" "$(runs)" "budget 0 counts as no consent: no run"
expect_has "$out" "Mogger evals" "budget 0: nudge shown instead"

echo "== quiet cases"
fresh; consent 5; export MOGGER_EVAL_BIN="$SANDBOX/does-not-exist.sh"
out=$(nudge); rc=0; nudge >/dev/null; rc=$?
expect_empty "$out" "engine missing (consented): quiet"
expect "0" "$rc" "engine missing: exit 0"
expect "0" "$(runs)" "engine missing: no run"
fresh; export MOGGER_EVAL_BIN="$SANDBOX/does-not-exist.sh"
expect_empty "$(nudge)" "engine missing (no consent): no nudge"
fresh; consent 5; export MOGGER_EVALS=off
out=$(nudge); rc=$?; wait_runs 1
expect_empty "$out" "MOGGER_EVALS=off: quiet"
expect "0" "$rc" "MOGGER_EVALS=off: exit 0"
expect "0" "$(runs)" "MOGGER_EVALS=off: no run"
expect "0" "$(ests)" "MOGGER_EVALS=off: engine never called"
fresh; export MOGGER_EVALS=off
expect_empty "$(nudge)" "MOGGER_EVALS=off: no nudge for new project"
[ ! -d "$D" ] && ok "MOGGER_EVALS=off: no state written" || bad "MOGGER_EVALS=off: no state written"

echo "== fail open"
fresh; mkdir -p "$D"; printf 'garbage{{{\n' > "$D/nudge.json"; printf '%%%%%%\n' > "$D/consent.json"
nudge >/dev/null; rc=$?
expect "0" "$rc" "garbage state files: exit 0"
: > "$SANDBOX/afile"; export CLAUDE_PROJECT_DIR="$SANDBOX/afile/sub"
out=$(nudge); rc=$?
expect "0" "$rc" "unwritable project dir: exit 0"
expect_empty "$out" "unwritable project dir: quiet"
fresh
out=$( ( source "$NUDGE"; evals_session_context ) 2>/dev/null )
expect_has "$out" "Mogger evals" "sourced function prints the nudge"
fresh; nudge >/dev/null
extra=$(cd "$P" && find . -type f | sort | tr '\n' ' ')
expect "./.claude/state/evals/nudge.json " "$extra" "nudge writes only its own state file"

echo "== speed"
fresh; consent 5
printf '{"fingerprint":"%s"}\n' "$(evals_fingerprint)" > "$D/last.json"
touch "$D/seen"
t0=$(now_s); i=0
while [ "$i" -lt 20 ]; do nudge >/dev/null; i=$((i+1)); done
t1=$(now_s)
[ $((t1 - t0)) -le 2 ] && ok "idle consented path: 20 runs in $((t1 - t0))s (<150ms each)" || bad "idle consented path too slow: $((t1 - t0))s for 20 runs"
fresh; mkdir -p "$D"; printf '{"state":"dismissed","shown_at":1}\n' > "$D/nudge.json"
t0=$(now_s); i=0
while [ "$i" -lt 20 ]; do nudge >/dev/null; i=$((i+1)); done
t1=$(now_s)
[ $((t1 - t0)) -le 2 ] && ok "idle dismissed path: 20 runs in $((t1 - t0))s (<150ms each)" || bad "idle dismissed path too slow: $((t1 - t0))s for 20 runs"
fresh; export MOGGER_EVALS=off
t0=$(now_s); i=0
while [ "$i" -lt 20 ]; do nudge >/dev/null; i=$((i+1)); done
t1=$(now_s)
[ $((t1 - t0)) -le 2 ] && ok "off path: 20 runs in $((t1 - t0))s" || bad "off path too slow: $((t1 - t0))s"

echo "== output style"
long=$(awk 'length($0) > 100 { n++ } END { print n + 0 }' "$ALLOUT")
expect "0" "$long" "all nudge output lines are 100 characters or fewer"
[ -s "$ALLOUT" ] && ok "captured output to check" || bad "captured output to check"

# ------------------------------------------------------------ evals-static.sh
echo "== evals-static: fixtures"
F="$SANDBOX/fx"; mkdir -p "$F/skills/alpha" "$F/skills/beta" "$F/skills/gamma" "$F/skills/wrongdir" "$F/skills/nodesc" "$F/agents"
mkskill() { printf -- '---\nname: %s\ndescription: %s\n---\nbody\n' "$2" "$3" > "$F/skills/$1/SKILL.md"; }
mkskill alpha alpha "Use when reviewing database migrations for schema drift, index coverage, rollback safety and foreign key constraints in production tables."
mkskill beta beta "Use when reviewing database migrations for schema drift, index coverage, rollback safety and foreign key constraints before deploy."
mkskill gamma gamma "Formats changelog entries in one consistent style with dates."
mkskill wrongdir other-name "Use when checking the folder name matches the skill name field."
printf -- '---\nname: nodesc\n---\nbody\n' > "$F/skills/nodesc/SKILL.md"
printf -- '---\nname: cheap\ndescription: Use when a quick lookup is needed.\ntools: Read, Write\nmodel: haiku\neffort: low\n---\nbody\n' > "$F/agents/cheap.md"
printf -- '---\nname: logger\ndescription: Use when logging is needed for a cheap run.\ntools: Read, Grep\nmodel: haiku\n---\nRun bash log-savings.sh at the end.\n' > "$F/agents/logger.md"
printf -- '---\nname: eff\ndescription: Use when a mid-tier task needs care.\ntools: Read\nmodel: sonnet\neffort: low\n---\nbody\n' > "$F/agents/eff.md"
printf -- '---\nname: notools\ndescription: Use when a cheap task has no tools list at all.\nmodel: haiku\n---\nbody\n' > "$F/agents/notools.md"
printf -- '---\nname: wrongfile\ndescription: Use when the file name differs from the name field.\ntools: Read\nmodel: sonnet\n---\nbody\n' > "$F/agents/otherfile.md"
printf -- '---\nname: short\ndescription: Use when.\nmodel: sonnet\n---\nbody\n' > "$F/agents/short.md"
before=$(cd "$F" && find . -type f | sort | xargs cksum | cksum)
out=$(bash "$STATIC" "$F"); rc=$?
after=$(cd "$F" && find . -type f | sort | xargs cksum | cksum)
expect "0" "$rc" "static: exits 0 with findings"
expect "$before" "$after" "static: does not modify the project"
LEVELS=$(printf '%s\n' "$out" | awk -F'|' 'NF >= 3 && $1 !~ /^(PASS|WARN|FAIL|SKIP)$/ { n++ } END { print n + 0 }')
expect "0" "$LEVELS" "static: every line is LEVEL|check-id|message"
expect_has "$out" "WARN|evals-overlap|skills/alpha/SKILL.md and skills/beta/SKILL.md" "overlap: names the pair"
expect_has "$out" "Shared:" "overlap: lists the shared words"
expect_has "$out" "migrations" "overlap: shared words include migrations"
expect_not "$out" "skills/gamma/SKILL.md and" "overlap: unrelated skill not paired"
expect_has "$out" "WARN|evals-trigger|skills/gamma/SKILL.md:" "trigger: skill without trigger phrasing flagged with file:line"
expect_not "$out" "evals-trigger|skills/alpha" "trigger: skill with 'Use when' not flagged"
expect_has "$out" "FAIL|evals-frontmatter|skills/nodesc/SKILL.md:1 skill has no description" "frontmatter: missing description is FAIL"
expect_has "$out" "WARN|evals-name-match|skills/wrongdir/SKILL.md" "name-match: skill name vs directory"
expect_has "$out" "WARN|evals-name-match|agents/otherfile.md" "name-match: agent name vs file"
expect_has "$out" 'agent "cheap" runs on Haiku and has Write or Edit' "haiku-write: Haiku agent with Write flagged"
expect_has "$out" 'agent "notools" runs on Haiku and has no tools list' "haiku-write: Haiku agent with no tools list flagged"
expect_not "$out" 'agent "logger" runs on Haiku and has Write' "haiku-write: read-only Haiku agent not flagged"
expect_has "$out" 'agents/logger.md:7 agent "logger" mentions log-savings but its tools list has no Bash' "log-bash: flagged with line"
expect_not "$out" 'agent "cheap" sets effort' "effort-tier: effort on Haiku not flagged"
expect_has "$out" 'agent "eff" sets effort: low on model "sonnet"' "effort-tier: effort on Sonnet flagged"
expect_has "$out" 'agent "short" ' "desc-length: fixture agent present"
expect_has "$out" "WARN|evals-desc-length|agents/short.md:3 agent \"short\" description is 9 characters (short" "desc-length: short description flagged"
expect_has "$out" "SKIP|evals-quality|" "quality: SKIP line present"
expect_has "$out" "scripts/mogger-eval.sh estimate" "quality: SKIP points at the estimate command"
expect_not "$out" "good enough|" "static: never says a model is good enough"

echo "== evals-static: long description, folded YAML, quotes, CRLF"
F2="$SANDBOX/fx2"; mkdir -p "$F2/skills/long" "$F2/skills/folded" "$F2/skills/crlf" "$F2/skills/quoted"
long=$(awk 'BEGIN { s = "Use when"; for (i = 0; i < 120; i++) s = s " word" i; print s }')
printf -- '---\nname: long\ndescription: %s\n---\n' "$long" > "$F2/skills/long/SKILL.md"
printf -- '---\nname: folded\ndescription: >\n  Use when the description is folded\n  over two lines like this one.\n---\n' > "$F2/skills/folded/SKILL.md"
printf -- '---\r\nname: crlf\r\ndescription: Use when the file has Windows line endings.\r\n---\r\n' > "$F2/skills/crlf/SKILL.md"
printf -- '---\nname: "quoted"\ndescription: "Use when the values are wrapped in quotes."\n---\n' > "$F2/skills/quoted/SKILL.md"
out=$(bash "$STATIC" "$F2")
expect_has "$out" "WARN|evals-desc-length|skills/long/SKILL.md:3 skill \"long\" description is" "long description flagged"
expect_has "$out" "mogger heuristic, not a documented limit" "long limit is labelled a heuristic"
expect_not "$out" "skills/folded" "folded YAML description parsed (no findings)"
expect_not "$out" "skills/crlf" "CRLF frontmatter parsed (no findings)"
expect_not "$out" "skills/quoted" "quoted values parsed (no findings)"
expect_not "$out" "FAIL|evals-frontmatter|" "no frontmatter FAIL in parse fixtures"

echo "== evals-static: clean fixture"
C="$SANDBOX/clean"; mkdir -p "$C/skills/lint-rules" "$C/skills/deploy-notes" "$C/agents"
printf -- '---\nname: lint-rules\ndescription: Style rules for shell scripts. Use when writing or reviewing bash code in this repository.\n---\nbody\n' > "$C/skills/lint-rules/SKILL.md"
printf -- '---\nname: deploy-notes\ndescription: Records release steps for the staging server. Triggers on "release notes" or "how do we deploy".\n---\nbody\n' > "$C/skills/deploy-notes/SKILL.md"
printf -- '---\nname: finder\ndescription: Locates files by name across the tree. Use whenever a path is unknown.\ntools: Read, Grep, Glob\nmodel: haiku\neffort: low\n---\nbody\n' > "$C/agents/finder.md"
printf -- '---\nname: builder2\ndescription: Implements one task from the board. Use after planning is done.\ntools: Read, Write, Edit, Bash\nmodel: sonnet\n---\nbody\n' > "$C/agents/builder2.md"
out=$(bash "$STATIC" "$C"); rc=$?
expect "0" "$rc" "clean: exit 0"
bad_lines=$(printf '%s\n' "$out" | grep -E '^(WARN|FAIL)\|' || true)
expect_empty "$bad_lines" "clean fixture: no WARN or FAIL"
npass=$(printf '%s\n' "$out" | grep -c '^PASS|')
expect "8" "$npass" "clean fixture: 8 PASS lines (one per check)"
expect_has "$out" "PASS|evals-overlap|" "clean fixture: overlap PASS"
expect_has "$out" "SKIP|evals-quality|" "clean fixture: quality SKIP"

echo "== evals-static: edge cases"
E="$SANDBOX/empty"; mkdir -p "$E"
out=$(bash "$STATIC" "$E"); rc=$?
expect "0" "$rc" "empty project: exit 0"
expect_has "$out" "SKIP|evals-static|no agents" "empty project: SKIP"
out=$(bash "$STATIC" "$SANDBOX/no-such-dir"); rc=$?
expect "0" "$rc" "missing dir: exit 0"
expect_has "$out" "SKIP|evals-static|" "missing dir: SKIP"
t0=$(now_s); bash "$STATIC" "$ROOT" > "$SANDBOX/self.out"; rc=$?; t1=$(now_s)
expect "0" "$rc" "real plugin repo: exit 0"
[ $((t1 - t0)) -lt 10 ] && ok "real plugin repo: under 10 seconds ($((t1 - t0))s)" || bad "real plugin repo: too slow ($((t1 - t0))s)"
badfmt=$(awk -F'|' 'NF < 3 || $1 !~ /^(PASS|WARN|FAIL|SKIP)$/ { n++ } END { print n + 0 }' "$SANDBOX/self.out")
expect "0" "$badfmt" "real plugin repo: every line is LEVEL|check-id|message"
[ -f "$ROOT/skills/mogger-evals/SKILL.md" ] && ok "skill mogger-evals exists" || bad "skill mogger-evals exists"
[ -f "$ROOT/skills/mogger-app-evals/SKILL.md" ] && ok "skill mogger-app-evals exists" || bad "skill mogger-app-evals exists"
sk=$(grep -E 'evals-(trigger|frontmatter|name-match)\|skills/mogger-(app-)?evals' "$SANDBOX/self.out" || true)
expect_empty "$sk" "new evals skills pass the free check (trigger, frontmatter, name)"
expect_has "$(cat "$ROOT/skills/mogger-evals/SKILL.md")" "consent --budget" "mogger-evals skill documents consent --budget"
expect_has "$(cat "$ROOT/skills/mogger-app-evals/SKILL.md")" "/claude-api build-eval" "mogger-app-evals names build-eval"
expect_has "$(cat "$ROOT/skills/mogger-init/SKILL.md")" "mogger-evals" "mogger-init offers the evals"

echo
echo "evals-ux: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
