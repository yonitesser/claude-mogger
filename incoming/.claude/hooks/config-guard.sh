#!/usr/bin/env bash
# PreToolUse hook — matches: Edit|Write|MultiEdit|Bash
# Asks the human before Claude changes the files that control Claude itself:
# .claude/settings.json, .claude/settings.local.json, anything in .claude/hooks/,
# and .mcp.json. A model that can edit its own guard rails can switch them off.
# Uses permissionDecision "ask": the human sees a normal permission prompt and
# can approve a change they asked for. Never blocks outright.
# Text matching only; a seat belt, not a sandbox.
# Escape hatch: MOGGER_CONFIG_GUARD=off.

source "$(dirname "$0")/lib.sh"
set -f   # no filename expansion while splitting words
[ "${MOGGER_CONFIG_GUARD:-on}" = "off" ] && exit 0

INPUT=$(cat)
CFG='(^|/)\.claude/(settings(\.local)?\.json|hooks/.+)$|(^|/)\.mcp\.json$'

ask() {  # ask <basename>
  mogger_event warn "asked before a change to $1"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s controls Claude and its guard rails. Approve only if you asked for this change."}}\n' "$1"
  exit 0
}

FILE_PATH=$(json_get "$INPUT" '.tool_input.file_path')
if [ -n "$FILE_PATH" ] && [[ "$FILE_PATH" =~ $CFG ]]; then
  ask "$(basename "$FILE_PATH")"
fi

CMD=$(json_get "$INPUT" '.tool_input.command')
[ -z "$CMD" ] && exit 0
CLEAN=$(printf '%s' "$CMD" | tr -d "\"'\`")
while IFS= read -r seg; do
  [ -z "$seg" ] && continue
  write=0; hit=""
  case "$seg" in *">"*) write=1 ;; esac
  case " $seg " in *" tee "*|*" cp "*|*" mv "*|*" rm "*|*" truncate "*|*" ln "*|*" install "*|*" dd "*) write=1 ;; esac
  case "$seg" in *"sed "*" -i"*|*"sed -i"*|*"perl -i"*|*"perl -pi"*) write=1 ;; esac
  for w in $seg; do
    for tok in $(printf '%s' "$w" | tr '=<>' '   '); do
      [[ "$tok" =~ $CFG ]] && hit="$tok"
    done
  done
  [ "$write" = 1 ] && [ -n "$hit" ] && ask "$(basename "$hit")"
done <<<"$(printf '%s' "$CLEAN" | tr ';|&' '\n\n\n')"

exit 0
