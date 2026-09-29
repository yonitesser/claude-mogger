#!/usr/bin/env bash
# PreToolUse hook — matches: Edit|Write
# DECISIONS.md is an append-only log. Blocks (exit 2) edits that alter or
# delete existing text. Allowed: creating the file, appending, and flipping
# one entry's "Status: active" to "Status: superseded-by #n".
# Escape hatch: MOGGER_DECISIONS_LOCK=off

source "$(dirname "$0")/lib.sh"
INPUT=$(cat)

[ "${MOGGER_DECISIONS_LOCK:-on}" = "off" ] && exit 0

FILE_PATH=$(json_get "$INPUT" '.tool_input.file_path')
[ -z "$FILE_PATH" ] && exit 0
[ "$(basename "$FILE_PATH")" = "DECISIONS.md" ] || exit 0
[ -f "$FILE_PATH" ] || exit 0   # fresh create is fine

TOOL=$(json_get "$INPUT" '.tool_name')

block() {
  echo "BLOCKED: DECISIONS.md is append-only. $1 Add a new entry at the end instead, and to retire an old one change only its 'Status: active' line to 'Status: superseded-by #n'. (Human override: MOGGER_DECISIONS_LOCK=off.)" >&2
  exit 2
}

if [ "$TOOL" = "Write" ]; then
  NEW=$(json_get "$INPUT" '.tool_input.content')
  OLD=$(cat "$FILE_PATH")
  [[ "$NEW" == "$OLD"* ]] || block "This Write would overwrite existing entries."
  exit 0
fi

# Edit
OLD=$(json_get "$INPUT" '.tool_input.old_string')
NEW=$(json_get "$INPUT" '.tool_input.new_string')
[ -z "$OLD" ] && exit 0
[[ "$NEW" == "$OLD"* ]] && exit 0
if [[ "$NEW" =~ superseded-by\ \#([0-9]+) ]]; then
  N="${BASH_REMATCH[1]}"
  [ "${OLD/Status: active/Status: superseded-by #$N}" = "$NEW" ] && exit 0
fi
block "This Edit changes or removes existing text."
