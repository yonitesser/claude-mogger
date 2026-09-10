#!/usr/bin/env bash
# PreToolUse — matcher: Task
# Reviewer may not run unless tester recorded a REAL pass (exit code 0) and
# nothing changed since. The gate is a file the model didn't get to write
# with its opinion — it wrote it with $?.
source "$(dirname "$0")/lib.sh"

INPUT=$(cat)
SUBAGENT=$(json_get "$INPUT" '.tool_input.subagent_type')
[ "$SUBAGENT" != "${MOGGER_REVIEWER_NAME:-reviewer}" ] && exit 0

MARKER=".claude/state/last_test_result.json"

if [ ! -f "$MARKER" ]; then
  echo "BLOCKED: no test result at $MARKER. Delegate to tester first — reviewer cannot run on an unverified change." >&2
  exit 2
fi

STATUS=$(json_get "$(cat "$MARKER")" '.status')
if [ "$STATUS" != "pass" ]; then
  echo "BLOCKED: last recorded test status is '${STATUS:-missing}', not 'pass'. Fix (builder), re-run tester, then reviewer." >&2
  exit 2
fi

# Stale check: any source file newer than the marker means the pass is for old code.
NEWER=$(find . -type f -newer "$MARKER" \
  -not -path './.git/*' -not -path './.claude/state/*' -not -path './node_modules/*' \
  -not -path './.venv/*' -not -path './target/*' -not -path './dist/*' -not -path './build/*' \
  -not -name 'RUNS.md' -not -name 'TASKS.md' 2>/dev/null | head -1)
if [ -n "$NEWER" ]; then
  echo "BLOCKED: '$NEWER' changed after the last test run. The pass is stale. Re-run tester." >&2
  exit 2
fi

exit 0
