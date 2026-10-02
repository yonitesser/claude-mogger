#!/usr/bin/env bash
# Tests for mogger_event (hooks/scripts/lib.sh): the one-line-per-event log that
# the mods/mogger-status mod reads. The helper must append, cap, sanitise, never
# print, never fail, and never change what a guard hook exits with or prints.
# Run: bash tests/mogger-events.test.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
H="$ROOT/hooks/scripts"
PASS=0; FAIL=0
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
export TMPDIR="$SANDBOX/tmp"; mkdir -p "$TMPDIR"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset MOGGER_SECRET_GUARD MOGGER_CHECKPOINT MOGGER_CHECKPOINT_INTERVAL MOGGER_ALLOW_PUSH

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
check() { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (want '$1', got '$2')"; fi; }

PROJ="$SANDBOX/proj"; mkdir -p "$PROJ"; cd "$PROJ"
git init -q -b main . 2>/dev/null || { git init -q .; git checkout -q -b main; }
echo base > a.txt; git add a.txt; git commit -q -m init
export CLAUDE_PROJECT_DIR="$PROJ"
LOG="$PROJ/.claude/state/mogger-events.log"

jstr() {
  if command -v jq >/dev/null 2>&1; then printf '%s' "$1" | jq -Rs .
  else printf '%s' "$1" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))'; fi
}
write_json() { printf '{"tool_name":"Write","tool_input":{"file_path":%s,"content":%s}}' "$(jstr "$1")" "$(jstr "$2")"; }
bash_json()  { printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(jstr "$1")"; }

echo "== helper"
OUT=$(bash -c 'source "$1"; mogger_event block "blocked a secret in config.js"; echo "rc=$?"' _ "$H/lib.sh" 2>&1)
check "rc=0" "$OUT" "prints nothing, returns 0"
[ -f "$LOG" ] && ok "creates .claude/state/mogger-events.log" || bad "log not created"
LINE=$(tail -n 1 "$LOG")
EPOCH=$(printf '%s' "$LINE" | cut -f1); KIND=$(printf '%s' "$LINE" | cut -f2); MSG=$(printf '%s' "$LINE" | cut -f3)
case "$EPOCH" in ''|*[!0-9]*) bad "epoch is a number ($EPOCH)" ;; *) ok "epoch is a number" ;; esac
check "block" "$KIND" "kind column"
check "blocked a secret in config.js" "$MSG" "message column"
check "3" "$(printf '%s' "$LINE" | awk -F'\t' '{print NF}')" "exactly 3 tab-separated columns"

bash -c 'source "$1"; mogger_event warn "line one
line two	tabbed"' _ "$H/lib.sh"
LINE=$(tail -n 1 "$LOG")
check "3" "$(printf '%s' "$LINE" | awk -F'\t' '{print NF}')" "newline and tab in a message cannot add columns"
check "1" "$(grep -c 'line two' "$LOG")" "a message stays on one line"

N0=$(wc -l < "$LOG" | tr -d ' ')
bash -c 'source "$1"; mogger_event "" "x"; mogger_event warn ""' _ "$H/lib.sh"
check "$N0" "$(wc -l < "$LOG" | tr -d ' ')" "empty kind or message writes nothing"

LONG=$(printf 'x%.0s' $(seq 1 400))
bash -c 'source "$1"; mogger_event warn "$2"' _ "$H/lib.sh" "$LONG"
check "120" "$(tail -n 1 "$LOG" | cut -f3 | tr -d '\n' | wc -c | tr -d ' ')" "message cut to 120 characters"

echo "== cap"
rm -f "$LOG"
bash -c 'source "$1"; i=0; while [ $i -lt 500 ]; do mogger_event ok "event $i"; i=$((i+1)); done' _ "$H/lib.sh"
CNT=$(wc -l < "$LOG" | tr -d ' ')
[ "$CNT" -le 240 ] && [ "$CNT" -ge 200 ] && ok "500 events keep the file between 200 and 240 lines ($CNT)" || bad "file has $CNT lines"
check "event 499" "$(tail -n 1 "$LOG" | cut -f3)" "newest event is kept"
check "0" "$(grep -c 'event 0$' "$LOG")" "oldest events are dropped"
ls "$PROJ/.claude/state" | grep -q '\.[0-9][0-9]*$' && bad "temp file left behind" || ok "no temp file left behind"

echo "== fails open"
OUT=$(CLAUDE_PROJECT_DIR=/dev/null/nope bash -c 'source "$1"; mogger_event block "x"; echo "rc=$?"' _ "$H/lib.sh" 2>&1)
check "rc=0" "$OUT" "unwritable location: silent, returns 0"
OUT=$(bash -c 'set -e; source "$1"; CLAUDE_PROJECT_DIR=/dev/null/nope mogger_event block "x"; echo alive' _ "$H/lib.sh" 2>&1)
check "alive" "$OUT" "does not trip set -e"

echo "== guards: same exit code and output with or without a writable log"
same() {  # same <hook> <json> <desc> [expected exit]
  local hook="$1" json="$2" desc="$3" want="${4:-}" a b ra rb
  a=$(printf '%s' "$json" | CLAUDE_PROJECT_DIR="$PROJ" bash "$H/$hook" 2>&1); ra=$?
  b=$(printf '%s' "$json" | CLAUDE_PROJECT_DIR=/dev/null/nope bash "$H/$hook" 2>&1); rb=$?
  if [ "$a" = "$b" ] && [ "$ra" = "$rb" ] && { [ -z "$want" ] || [ "$ra" = "$want" ]; }; then ok "$hook: $desc (exit $ra)"; else bad "$hook: $desc (exit $ra vs $rb, output differs: $([ "$a" = "$b" ] && echo no || echo yes))"; fi
}
rm -f "$LOG"
AWS="AKIA""IOSFODNN7QWERTYU"
same protect-pipeline-files.sh "$(write_json "$PROJ/.github/workflows/ci.yml" x)" "blocks a workflow edit" 2
same protect-pipeline-files.sh "$(write_json "$PROJ/src/app.js" x)" "allows a normal file" 0
same secret-guard.sh "$(write_json "$PROJ/config.js" "const k = '$AWS'")" "blocks a secret" 2
same secret-guard.sh "$(write_json "$PROJ/.env" "A=1")" "blocks .env" 2
same secret-guard.sh "$(write_json "$PROJ/ok.js" "const a = 1")" "allows clean code" 0
same require-approval.sh "$(bash_json "git push origin feature")" "blocks git push" 2
same require-approval.sh "$(bash_json "ls -la")" "allows ls" 0
same secret-guard-bash.sh "$(bash_json "git add -f dist/x")" "blocks git add -f" 2

echo "== log content"
rm -f "$LOG"
printf '%s' "$(write_json "$PROJ/config.js" "const k = '$AWS'")" | bash "$H/secret-guard.sh" >/dev/null 2>&1
check "block" "$(tail -n 1 "$LOG" | cut -f2)" "secret-guard logs a block"
check "blocked a secret in config.js" "$(tail -n 1 "$LOG" | cut -f3)" "message names the basename only"
grep -q "$AWS" "$LOG" && bad "secret value leaked into the log" || ok "secret value is not in the log"
grep -q "$PROJ" "$LOG" && bad "full path leaked into the log" || ok "full path is not in the log"
rm -f "$LOG"
printf '%s' "$(bash_json "git push origin feature")" | bash "$H/require-approval.sh" >/dev/null 2>&1
grep -q 'feature\|origin' "$LOG" && bad "command text leaked into the log" || ok "command text is not in the log"
check "blocked git push" "$(tail -n 1 "$LOG" | cut -f3)" "require-approval logs a block"
rm -f "$LOG"
printf '%s' "$(write_json "$PROJ/ok.js" "const a = 1")" | bash "$H/secret-guard.sh" >/dev/null 2>&1
[ -f "$LOG" ] && bad "a passing hook wrote to the log" || ok "a passing hook writes nothing"

echo "== checkpoint"
rm -f "$LOG"
printf '%s' "$(write_json "$PROJ/a.txt" x)" | bash "$H/checkpoint.sh" >/dev/null 2>&1
check "ok" "$(tail -n 1 "$LOG" | cut -f2)" "checkpoint logs an ok event"
N1=$(git for-each-ref refs/mogger/checkpoints | wc -l | tr -d ' ')
printf '%s' "$(write_json "$PROJ/a.txt" x)" | MOGGER_CHECKPOINT_INTERVAL=0 bash "$H/checkpoint.sh" >/dev/null 2>&1
check "$N1" "$(git for-each-ref refs/mogger/checkpoints | wc -l | tr -d ' ')" "the log file does not make the tree look changed"
CP=$(git for-each-ref --format='%(refname)' refs/mogger/checkpoints | head -n 1)
git ls-tree -r --name-only "$CP" | grep -q 'mogger-events.log' && bad "log is inside a checkpoint" || ok "log is not inside a checkpoint"

echo
echo "  mogger-events: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
