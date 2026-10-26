#!/usr/bin/env bash
# PreToolUse — matcher: Task
# Reviewer may not run unless the tests were run and recorded a REAL pass (exit code 0) and
# nothing changed since. The gate is a file the model didn't get to write
# with its opinion — it wrote it with $?.
source "${0%/*}/lib.sh"

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
  mogger_event block "blocked review: no test result"; echo "BLOCKED: no test result at $MARKER. Run the tests first and write the marker (see skills/loop/doing.md) — reviewer cannot run on an unverified change." >&2
  exit 2
fi

STATUS=$(json_get "$(cat "$MARKER")" '.status')
if [ "$STATUS" != "pass" ]; then
  mogger_event block "blocked review: tests did not pass"; echo "BLOCKED: last recorded test status is '${STATUS:-missing}', not 'pass'. Fix, re-run the tests, then reviewer." >&2
  exit 2
fi

# The marker above is the Lead's claim. A hook (record-test-run.sh) records
# what the test command really returned; the gate needs that to say "pass" too.
# MOGGER_EVIDENCE=off skips this (projects whose test command the hook can't see).
EVID=".claude/state/test-evidence.json"
if [ "${MOGGER_EVIDENCE:-on}" != "off" ]; then
  if [ ! -f "$EVID" ]; then
    mogger_event block "blocked review: no hook-recorded test run"; echo "BLOCKED: the marker says pass, but no test run was recorded by the hook ($EVID). Run the project's test command through Bash (e.g. npm test, pytest, go test). For a custom command set MOGGER_TEST_CMD_REGEX, or MOGGER_EVIDENCE=off to skip this check." >&2
    exit 2
  fi
  ESTATUS=$(json_get "$(cat "$EVID")" '.status')
  if [ "$ESTATUS" != "pass" ]; then
    mogger_event block "blocked review: last real test run failed"; echo "BLOCKED: the last test run seen by the hook was '${ESTATUS:-unknown}', whatever the marker says. Fix, re-run the tests, then reviewer." >&2
    exit 2
  fi
  # stale check below is against the evidence file (the marker could be touched by hand)
  MARKER="$EVID"
fi

# An affected-tests-only pass is not enough to send something to review.
# The Lead runs targeted subsets during the build loop for speed, then a
# full suite once at the end — reviewer needs the full one.
SCOPE=$(json_get "$(cat .claude/state/last_test_result.json)" '.scope')
if [ -n "$SCOPE" ] && [ "$SCOPE" != "full" ]; then
  mogger_event block "blocked review: tests ran on a part only"; echo "BLOCKED: last test run was scope '$SCOPE', not 'full'. Affected-only runs are for the build loop; reviewer requires a full-suite pass. Re-run the complete suite." >&2
  exit 2
fi

# Stale check: any source file newer than the marker means the pass is for old code.
NEWER=$(find . -type f -newer "$MARKER" \
  -not -path './.git/*' -not -path './.claude/state/*' -not -path './node_modules/*' \
  -not -path './.venv/*' -not -path './target/*' -not -path './dist/*' -not -path './build/*' \
  -not -name 'RUNS.md' -not -name 'TASKS.md' -not -name 'STATUS.md' 2>/dev/null | head -1)
if [ -n "$NEWER" ]; then
  mogger_event block "blocked review: test pass is stale"; echo "BLOCKED: '$NEWER' changed after the last test run. The pass is stale. Re-run the tests." >&2
  exit 2
fi

exit 0
