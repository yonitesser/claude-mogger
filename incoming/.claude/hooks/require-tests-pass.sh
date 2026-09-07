#!/usr/bin/env bash
# PreToolUse hook — matches: Task
# This is the "gate can't be the thing it's grading" fix. Reviewer is an
# LLM judging LLM-written code — that's fine for code quality, but it must
# not be trusted to also self-certify that tests passed. This hook checks
# the actual exit code tester recorded, not tester's prose claim.

INPUT=$(cat)
SUBAGENT=$(echo "$INPUT" | jq -r '.tool_input.subagent_type // empty')

if [ "$SUBAGENT" != "reviewer" ]; then
  exit 0
fi

MARKER=".claude/state/last_test_result.json"

if [ ! -f "$MARKER" ]; then
  echo "BLOCKED: no test result found at $MARKER. Delegate to tester first — reviewer cannot run on an unverified change." >&2
  exit 2
fi

STATUS=$(jq -r '.status // empty' "$MARKER" 2>/dev/null)
TIMESTAMP=$(jq -r '.timestamp // empty' "$MARKER" 2>/dev/null)

if [ "$STATUS" != "pass" ]; then
  echo "BLOCKED: last recorded test status is '$STATUS', not 'pass'. Fix the failure (builder) and re-run tester before reviewer." >&2
  exit 2
fi

# Staleness check: marker must be newer than the most recent file edit,
# otherwise it may be reporting on a previous version of the code.
if [ -n "$TIMESTAMP" ]; then
  MARKER_EPOCH=$(date -d "$TIMESTAMP" +%s 2>/dev/null || echo 0)
  NEWEST_EDIT=$(find . -newer "$MARKER" -type f -not -path './.git/*' -not -path './.claude/state/*' 2>/dev/null | head -1)
  if [ -n "$NEWEST_EDIT" ]; then
    echo "BLOCKED: '$NEWEST_EDIT' changed after the last test run. The pass result is stale. Re-run tester." >&2
    exit 2
  fi
fi

exit 0
