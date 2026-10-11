#!/usr/bin/env bash
# PreToolUse hook — matches: Edit|Write
# Blocks edits to files that control deployment pipelines or payments.
# Agents can still read these files, just not change them unsupervised.

source "$(dirname "$0")/lib.sh"
INPUT=$(cat)
FILE_PATH=$(json_get "$INPUT" '.tool_input.file_path')

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# test evidence is written by record-test-run.sh from real runs, never by the model
case "$FILE_PATH" in
  *.claude/state/test-evidence.json*)
    mogger_event block "blocked a write to the test evidence file"; echo "BLOCKED: '$FILE_PATH' is written by a hook from real test runs. Run the tests instead of writing it." >&2
    exit 2 ;;
esac

if echo "$FILE_PATH" | grep -qiE '(\.github/workflows/|\.gitlab-ci\.yml|Dockerfile|docker-compose.*\.yml|terraform/|\.tf$|stripe|billing|payment)'; then
  mogger_event block "blocked an edit of ${FILE_PATH##*/}"; echo "BLOCKED: '$FILE_PATH' controls deployment or payments. Editing it requires human approval. Explain the change you want to make instead of making it." >&2
  exit 2
fi

exit 0
