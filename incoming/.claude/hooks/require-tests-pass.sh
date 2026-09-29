#!/usr/bin/env bash
# PreToolUse — matcher: Task
# Reviewer may not run unless tester recorded a REAL pass (exit code 0) and
# nothing changed since. The gate is a file the model didn't get to write
# with its opinion — it wrote it with $?.
source "$(dirname "$0")/lib.sh"

INPUT=$(cat)
SUBAGENT=$(json_get "$INPUT" '.tool_input.subagent_type')

# Two gating modes:
#   default        — gate only the agent named by MOGGER_REVIEWER_NAME (default "reviewer")
#   GATE_ALL_TASKS — gate EVERY Task dispatch on a passing full-suite run.
# The second exists for composing with an external framework (Superpowers,
# ECC, gstack) whose subagent names you don't control and may not be able
# to predict. Name-based gating silently does nothing if the name never
# matches, which is the worst failure mode a safety gate can have: it
# looks installed and enforces nothing.
if [ "${MOGGER_GATE_ALL_TASKS:-off}" != "on" ]; then
  [ "$SUBAGENT" != "${MOGGER_REVIEWER_NAME:-reviewer}" ] && exit 0
else
  # Exempt the agents whose whole job is to run before/produce the tests —
  # gating those would deadlock (can't test until tests pass).
  case "$SUBAGENT" in
    tester|builder|explorer|bulk-reader|code-writer|library-scout|planner) exit 0 ;;
  esac
  # Also exempt anything matching a user-supplied allowlist pattern.
  if [ -n "${MOGGER_GATE_EXEMPT:-}" ] && [[ "$SUBAGENT" =~ ^(${MOGGER_GATE_EXEMPT})$ ]]; then
    exit 0
  fi
fi

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

# An affected-tests-only pass is not enough to send something to review.
# tester runs targeted subsets during the build loop for speed, then a
# full suite once at the end — reviewer needs the full one.
SCOPE=$(json_get "$(cat "$MARKER")" '.scope')
if [ -n "$SCOPE" ] && [ "$SCOPE" != "full" ]; then
  echo "BLOCKED: last test run was scope '$SCOPE', not 'full'. Affected-only runs are for the build loop; reviewer requires a full-suite pass. Re-run tester with the complete suite." >&2
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
