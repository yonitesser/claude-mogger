#!/usr/bin/env bash
# PreToolUse hook — matches: Edit|Write
# Blocks edits to files that control deployment pipelines or payments.
# Agents can still read these files, just not change them unsupervised.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

if echo "$FILE_PATH" | grep -qiE '(\.github/workflows/|\.gitlab-ci\.yml|Dockerfile|docker-compose.*\.yml|terraform/|\.tf$|stripe|billing|payment)'; then
  echo "BLOCKED: '$FILE_PATH' controls deployment or payments. Editing it requires human approval. Explain the change you want to make instead of making it." >&2
  exit 2
fi

exit 0
