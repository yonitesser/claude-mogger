#!/usr/bin/env bash
# PreToolUse — matcher: Task
# Opt-in companion to require-tests-pass.sh. When MOGGER_REQUIRE_SMOKE=on,
# reviewer may not run unless scripts/smoke-check.sh recorded ok:true in
# .claude/state/smoke.json and nothing changed since. Default OFF (fail open)
# so projects without a runnable app are never wedged.
source "$(dirname "$0")/lib.sh"

[ "${MOGGER_REQUIRE_SMOKE:-off}" != "on" ] && exit 0

INPUT=$(cat)
SUBAGENT=$(json_get "$INPUT" '.tool_input.subagent_type')

# Same two gating modes as require-tests-pass.sh.
if [ "${MOGGER_GATE_ALL_TASKS:-off}" != "on" ]; then
  [ "$SUBAGENT" != "${MOGGER_REVIEWER_NAME:-reviewer}" ] && exit 0
else
  case "$SUBAGENT" in
    tester|builder|explorer|bulk-reader|code-writer|library-scout|planner|verifier) exit 0 ;;
  esac
  if [ -n "${MOGGER_GATE_EXEMPT:-}" ] && [[ "$SUBAGENT" =~ ^(${MOGGER_GATE_EXEMPT})$ ]]; then
    exit 0
  fi
fi

MARKER=".claude/state/smoke.json"

if [ ! -f "$MARKER" ]; then
  mogger_event block "blocked review: no smoke result"; echo "BLOCKED: no smoke result at $MARKER. Delegate to verifier (scripts/smoke-check.sh) first — reviewer cannot run on a change nobody has seen run." >&2
  exit 2
fi

OK=$(json_get "$(cat "$MARKER")" '.ok')
if [ "$OK" != "true" ]; then
  mogger_event block "blocked review: smoke check did not pass"; echo "BLOCKED: last smoke check did not pass (see $MARKER). Fix (builder), re-run verifier, then reviewer." >&2
  exit 2
fi

NEWER=$(find . -type f -newer "$MARKER" \
  -not -path './.git/*' -not -path './.claude/state/*' -not -path './node_modules/*' \
  -not -path './.venv/*' -not -path './target/*' -not -path './dist/*' -not -path './build/*' \
  -not -path './.next/*' -not -name '__pycache__' -not -name '*.pyc' \
  -not -name 'RUNS.md' -not -name 'TASKS.md' 2>/dev/null | head -1)
if [ -n "$NEWER" ]; then
  mogger_event block "blocked review: smoke pass is stale"; echo "BLOCKED: '$NEWER' changed after the last smoke check. The pass is stale. Re-run verifier." >&2
  exit 2
fi

exit 0
