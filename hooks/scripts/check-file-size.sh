#!/usr/bin/env bash
# PreToolUse hook — matches: Read
# Blocks direct reads of big files. Tells Claude to use the bulk-reader
# subagent (Haiku) instead. Targeted reads (small files) pass through.

THRESHOLD="${MOGGER_READ_LINES:-350}"  # lines. Off: MOGGER_READ_GUARD=off. Tune: MOGGER_READ_LINES.

source "$(dirname "$0")/lib.sh"
[ "${MOGGER_READ_GUARD:-on}" = "off" ] && exit 0
INPUT=$(cat)
FILE_PATH=$(json_get "$INPUT" '.tool_input.file_path')

if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
  exit 0  # nothing to check, let it through
fi

# Images and PDFs are not line text. Claude reads them as pictures/pages,
# so the line limit does not apply.
case "$(printf '%s' "${FILE_PATH##*.}" | tr 'A-Z' 'a-z')" in
  png|jpg|jpeg|gif|webp|bmp|ico|heic|pdf) exit 0 ;;
esac

LINES=$(wc -l < "$FILE_PATH" 2>/dev/null || echo 0)

if [ "$LINES" -gt "$THRESHOLD" ]; then
  mogger_event block "blocked a big file read: ${FILE_PATH##*/}"; echo "BLOCKED: '$FILE_PATH' has $LINES lines (limit: $THRESHOLD). Do not Read this file directly. Instead, delegate to the bulk-reader subagent (Task tool, subagent_type: bulk-reader) and ask it the specific question you need answered from this file." >&2
  exit 2
fi

exit 0
