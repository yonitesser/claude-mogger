#!/usr/bin/env bash
# PreToolUse hook — matches: Edit|Write|MultiEdit|Bash
# Asks the human before Claude changes the files that control Claude itself:
# .claude/settings.json, .claude/settings.local.json, .claude/mogger.json (the
# guard switches; smoke settings live there too and also ask), anything in
# .claude/hooks/, and .mcp.json. A model that can edit its own guard rails can switch them off.
# Uses permissionDecision "ask": the human sees a normal permission prompt and
# can approve a change they asked for. Where no prompt can be shown (headless,
# bypass or auto mode) it blocks instead, so Claude cannot approve for itself.
# Text matching only; a seat belt, not a sandbox.
# States (MOGGER_CONFIG_GUARD): ask (default), off = allow.

source "${0%/*}/lib.sh"
set -f   # no filename expansion while splitting words
[ "$(mogger_state MOGGER_CONFIG_GUARD ask)" = "off" ] && exit 0

INPUT=$(cat)
CFG='(^|/)\.claude/(settings(\.local)?\.json|mogger\.json|hooks/.+)$|(^|/)\.mcp\.json$'

ask() {  # ask <basename>
  if ! mogger_can_ask "$INPUT"; then
    mogger_event block "blocked a change to $1 (no prompt available)"
    echo "BLOCKED: $1 controls Claude and its guard rails, and this session cannot show a prompt. Ask the human to make the change." >&2
    exit 2
  fi
  mogger_event warn "asked before a change to $1"
  mogger_ask_json "$1 controls Claude and its guard rails. Approve only if you asked for this change."
  exit 0
}

json_fields "$INPUT" .tool_input.file_path .tool_input.command
FILE_PATH="${JF[0]}"
if [ -n "$FILE_PATH" ] && [[ "$FILE_PATH" =~ $CFG ]]; then
  ask "${FILE_PATH##*/}"
fi

CMD="${JF[1]}"
[ -z "$CMD" ] && exit 0
# pure bash from here (this hook runs on every Bash call); `2>&1` and `>/dev/null` are not writes
shopt -s extglob
CLEAN=${CMD//[\"\'\`]/}
CLEAN=${CLEAN//>&[0-9-]/}
CLEAN=${CLEAN//>?(>)*([[:space:]])\/dev\/null/}
while IFS= read -r seg; do
  [ -z "$seg" ] && continue
  write=0; hit=""
  case "$seg" in *">"*) write=1 ;; esac
  case " $seg " in *" tee "*|*" cp "*|*" mv "*|*" rm "*|*" truncate "*|*" ln "*|*" install "*|*" dd "*) write=1 ;; esac
  case "$seg" in *"sed "*" -i"*|*"sed -i"*|*"perl -i"*|*"perl -pi"*) write=1 ;; esac
  for w in $seg; do
    wt=${w//[=<>]/ }
    for tok in $wt; do
      [[ "$tok" =~ $CFG ]] && hit="$tok"
    done
  done
  [ "$write" = 1 ] && [ -n "$hit" ] && ask "${hit##*/}"
done <<<"${CLEAN//[;|&]/$'\n'}"

exit 0
