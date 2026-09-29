#!/usr/bin/env bash
# PreToolUse hook — matches: Read
# Blocks direct reads of big files. Tells Claude to use the bulk-reader
# subagent (Haiku) instead. Targeted reads (small files) pass through.

THRESHOLD=350  # lines. Change this number to tune it.

source "$(dirname "$0")/lib.sh"
INPUT=$(cat)
FILE_PATH=$(json_get "$INPUT" '.tool_input.file_path')

if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
  exit 0  # nothing to check, let it through
fi

LINES=$(wc -l < "$FILE_PATH" 2>/dev/null || echo 0)

if [ "$LINES" -gt "$THRESHOLD" ]; then
  echo "BLOCKED: '$FILE_PATH' has $LINES lines (limit: $THRESHOLD). Do not Read this file directly. Instead, delegate to the bulk-reader subagent (Task tool, subagent_type: bulk-reader) and ask it the specific question you need answered from this file." >&2
  exit 2
fi

exit 0
