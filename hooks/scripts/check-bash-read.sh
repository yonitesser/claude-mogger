#!/usr/bin/env bash
# PreToolUse hook — matches: Bash
# Catches attempts to dodge the Read hook by using cat/head/tail/less/more
# on a big file from the shell instead.

THRESHOLD=350

source "$(dirname "$0")/lib.sh"
INPUT=$(cat)
CMD=$(json_get "$INPUT" '.tool_input.command')

# Only look at simple read-style commands, not every Bash call
if ! echo "$CMD" | grep -qE '^\s*(cat|head|tail|less|more)\s'; then
  exit 0
fi

# Pull the last whitespace-separated token as the likely file path
FILE_PATH=$(echo "$CMD" | awk '{print $NF}')

if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

LINES=$(wc -l < "$FILE_PATH" 2>/dev/null || echo 0)

if [ "$LINES" -gt "$THRESHOLD" ]; then
  echo "BLOCKED: '$FILE_PATH' has $LINES lines (limit: $THRESHOLD). Don't read it via Bash either. Delegate to the bulk-reader subagent (Task tool, subagent_type: bulk-reader) instead." >&2
  exit 2
fi

exit 0
