#!/usr/bin/env bash
# Stop — no matcher
# If this turn changed code files but touched no test file, send the model back
# ONCE to add tests for the new behaviour. Reads .claude/state/edits.log (written
# by track-edits.sh) and clears it, so each turn is judged on its own.
# Silent when tests were touched, when only docs/config changed, when the turn
# made fewer than MOGGER_TESTS_ADDED_MIN (default 3) code edits (a typo fix is
# not a feature), or when the hook already fired this stop. Costs nothing unless it blocks.
# Escape hatch: MOGGER_TESTS_ADDED=off
source "$(dirname "$0")/lib.sh"
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
MIN="${MOGGER_TESTS_ADDED_MIN:-3}"
case "$MIN" in ''|*[!0-9]*) MIN=3 ;; esac
[ "$CODE" -ge "$MIN" ] && [ "$TESTS" -eq 0 ] || exit 0
mogger_event block "stopped with code changes and no tests"
echo "NO TESTS: you changed code (${FILES}) but added or updated no test. Add tests for the new behaviour (one per behaviour you changed, including the error case), run the suite, then finish." >&2
exit 2
