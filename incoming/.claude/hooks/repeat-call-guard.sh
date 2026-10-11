#!/usr/bin/env bash
# PostToolUse AND PostToolUseFailure — no matcher (every tool)
# Stops "same call again and again" loops. Idea from arXiv 2609.20804
# (harness study): nudge at 5 identical calls in a row, stop at 8 identical
# failing calls. fix-loop-guard.sh only watches test/build commands; this
# watches every tool. Any different call in between resets the count.
# State: .claude/state/repeat-call.txt ("<signature> <count>").
# Escape hatch: MOGGER_REPEAT_GUARD=off. Fails OPEN on missing tools or bad input.

source "$(dirname "$0")/lib.sh"
[ "${MOGGER_REPEAT_GUARD:-on}" = "off" ] && exit 0

INPUT=$(cat)
[ -n "$INPUT" ] || exit 0
TOOL=$(json_get "$INPUT" '.tool_name')
[ -n "$TOOL" ] || exit 0
ARGS=$(json_get "$INPUT" '.tool_input')
EVENT=$(json_get "$INPUT" '.hook_event_name')
SIG=$(printf '%s|%s' "$TOOL" "$ARGS" | cksum | tr -d ' ')

DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/state"
F="$DIR/repeat-call.txt"
mkdir -p "$DIR" 2>/dev/null || exit 0

PREV=""; N=0
[ -f "$F" ] && read -r PREV N < "$F" 2>/dev/null
case "$N" in ''|*[!0-9]*) N=0 ;; esac
if [ "$PREV" = "$SIG" ]; then N=$((N+1)); else N=1; fi
printf '%s %s\n' "$SIG" "$N" > "$F" 2>/dev/null || exit 0

if [ "$EVENT" = "PostToolUseFailure" ] && [ "$N" -ge 8 ]; then
  mogger_event block "same failing call $N times"
  echo "mogger: this $TOOL call failed $N times in a row with the same input. STOP. Read the error, then try a DIFFERENT approach, or tell the user what blocks you." >&2
  exit 2
fi
if [ "$N" -eq 5 ]; then
  TEXT="You made this same $TOOL call 5 times in a row. Repeating it will not give a new result. Read the output you already have and take a different step."
  mogger_event hint "same call 5 times in a row"
  echo "mogger: $TEXT" >&2
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "${EVENT:-PostToolUse}" "$TEXT"
fi
exit 0
