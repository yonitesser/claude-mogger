#!/usr/bin/env bash
# PreToolUse hook — matches: Bash
# Hints (never blocks) when a command is known to print a lot and is not
# piped through tail/head/grep. Long output hides the one failing line.
# Escape hatch: MOGGER_HINT=off.

source "${0%/*}/lib.sh"
[ "${MOGGER_HINT:-on}" = "off" ] && exit 0

INPUT=$(cat)
CMD=$(json_get "$INPUT" '.tool_input.command')
[ -z "$CMD" ] && exit 0

# Already trimmed, redirected, or limited: say nothing.
if mogger_re "$CMD" '\||>|(^|[[:space:]])(-n|--max-count|--oneline|-q|--quiet|--silent)([[:space:]=]|$)|git[[:space:]]+log[[:space:]]+-[0-9]'; then
  exit 0
fi

# Known noisy commands: test runners, builds, long listings and logs.
NOISY='^[[:space:]]*(npm[[:space:]]+(run[[:space:]]+)?(test|build|ls)|yarn[[:space:]]+(test|build)|pnpm[[:space:]]+(run[[:space:]]+)?(test|build)|pytest|python3?[[:space:]]+-m[[:space:]]+pytest|go[[:space:]]+(test|build)|cargo[[:space:]]+(test|build)|mvn[[:space:]]|gradle[[:space:]]|\./gradlew|jest|vitest|git[[:space:]]+log|docker[[:space:]]+logs|journalctl|pip[[:space:]]+list|find[[:space:]]+/[[:space:]])'
mogger_re "$CMD" "$NOISY" || exit 0

TEXT="This command can print a lot. Add | tail -n 80 or | grep to keep only the failing lines."
# A bare full-suite run in the middle of a task: point at the related-tests picker (toggle: related-tests)
if [ "${MOGGER_RELATED_TESTS:-on}" != off ] && mogger_re "$CMD" '^[[:space:]]*(npm[[:space:]]+(run[[:space:]]+)?test|yarn[[:space:]]+test|pnpm[[:space:]]+(run[[:space:]]+)?test|pytest|python3?[[:space:]]+-m[[:space:]]+pytest|go[[:space:]]+test|cargo[[:space:]]+test|jest|vitest)([[:space:]]*$|[[:space:]]+(\.\/\.\.\.|-q|--silent))'; then
  TEXT="$TEXT Mid-task? related-tests.sh (in the mogger hooks folder) prints only the tests for the changed files. The full suite runs before done."
fi
mogger_event hint "noisy bash command without a pipe"
echo "mogger: $TEXT" >&2
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "$TEXT"
exit 0
