#!/usr/bin/env bash
# Stop — no matcher
# If this turn changed code files but touched no test file, send the model back
# ONCE to add tests for the new behaviour. Reads .claude/state/edits.log (written
# by track-edits.sh) and clears it, so each turn is judged on its own.
# Silent when tests were touched, when only docs/config changed, when the turn
# made fewer than MOGGER_TESTS_ADDED_MIN (default 3) code edits (a typo fix is
# not a feature), or when the hook already fired this stop. Costs nothing unless it blocks.
# Escape hatch: MOGGER_TESTS_ADDED=off
# Also runs the project's own test command before the turn may end, when code or
# tests changed (fast timeout). The model cannot claim "done" over a red suite.
# Costs no tokens when green; on red it hands back the last lines of output.
# Escape hatch: MOGGER_STOP_TESTS=off. Timeout: MOGGER_STOP_TESTS_TIMEOUT (default 90s).
source "$(dirname "$0")/lib.sh"

# Print the test command for this project, nothing if none is clearly set up.
stop_test_cmd() {
  if [ -f package.json ]; then
    local t; t=$(json_get "$(cat package.json)" '.scripts.test')
    case "$t" in ''|*"no test specified"*) ;; *) echo "npm test --silent"; return ;; esac
  fi
  if [ -f pytest.ini ] || [ -f tox.ini ] || { [ -f pyproject.toml ] && grep -q 'pytest' pyproject.toml; }; then
    python3 -c 'import pytest' 2>/dev/null && { echo "python3 -m pytest -x -q"; return; }
  fi
  [ -f go.mod ] && { echo "go test ./..."; return; }
  [ -f Cargo.toml ] && { echo "cargo test -q"; return; }
}

[ "${MOGGER_TESTS_ADDED:-on}" = "off" ] && exit 0
INPUT=$(cat)
LOG=".claude/state/edits.log"
[ -f "$LOG" ] || exit 0
CODE=$(grep -c '^C ' "$LOG" 2>/dev/null); CODE=${CODE:-0}
TESTS=$(grep -c '^T ' "$LOG" 2>/dev/null); TESTS=${TESTS:-0}
FILES=$(grep '^C ' "$LOG" | cut -c3- | sort -u | head -5 | tr '\n' ' ')
ACTIVE=$(json_get "$INPUT" '.stop_hook_active')
: > "$LOG" 2>/dev/null
[ "$ACTIVE" = "true" ] && exit 0
if [ "${MOGGER_STOP_TESTS:-on}" != "off" ] && [ $((CODE + TESTS)) -gt 0 ]; then
  CMD=$(stop_test_cmd)
  if [ -n "$CMD" ]; then
    OUT=$(timeout "${MOGGER_STOP_TESTS_TIMEOUT:-90}" bash -c "$CMD" 2>&1); RC=$?
    if [ "$RC" -ne 0 ] && [ "$RC" -ne 124 ]; then
      mogger_event block "stopped with failing tests"
      printf 'TESTS FAIL: "%s" exited %s. Fix the code (not the tests), run it again, then finish. Last output:\n%s\n' "$CMD" "$RC" "$(printf '%s' "$OUT" | tail -n 25 | cut -c1-300)" >&2
      exit 2
    fi
  fi
fi
MIN="${MOGGER_TESTS_ADDED_MIN:-3}"
case "$MIN" in ''|*[!0-9]*) MIN=3 ;; esac
[ "$CODE" -ge "$MIN" ] && [ "$TESTS" -eq 0 ] || exit 0
mogger_event block "stopped with code changes and no tests"
echo "NO TESTS: you changed code (${FILES}) but added or updated no test. Add tests for the new behaviour (one per behaviour you changed, including the error case), run the suite, then finish." >&2
exit 2
