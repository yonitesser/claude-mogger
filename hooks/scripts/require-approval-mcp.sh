#!/usr/bin/env bash
# PreToolUse — matcher: mcp__github__merge_pull_request, push_files, ... (see hooks.json)
# The Bash gate (require-approval.sh) cannot see GitHub tools that Claude calls
# through MCP. This one covers them with the same rules:
#   merging a PR, enabling auto-merge, deleting a repo/file: always blocked.
#   push_files / create_or_update_file / delete_file (they commit straight to a
#   branch): blocked unless MOGGER_ALLOW_PUSH=on, and never on a protected branch.
# Tool names are matched on the part after the last "__", so other servers with
# the same tool names (github enterprise, gitlab-style names) are covered too.
source "$(dirname "$0")/lib.sh"

INPUT=$(cat)
TOOL=$(json_get "$INPUT" '.tool_name')
[ -n "$TOOL" ] || exit 0
NAME="${TOOL##*__}"

case "$NAME" in
  merge_pull_request|enable_pr_auto_merge|delete_repository|delete_branch)
    mogger_event block "blocked MCP $NAME"; echo "BLOCKED: $NAME merges or deletes on GitHub and needs human approval. Report that the work is ready and stop." >&2
    exit 2 ;;
  push_files|create_or_update_file|delete_file)
    if [ "${MOGGER_ALLOW_PUSH:-off}" != "on" ]; then
      mogger_event block "blocked MCP $NAME"; echo "BLOCKED: $NAME commits straight to a remote branch and needs human approval. Do not retry with another tool." >&2
      exit 2
    fi
    BR=$(json_get "$INPUT" '.tool_input.branch')
    if [ -z "$BR" ] || is_protected_branch "${BR#refs/heads/}"; then
      mogger_event block "blocked MCP $NAME on a protected or unnamed branch"; echo "BLOCKED: $NAME needs an explicit feature branch (got '${BR:-none}'). Protected branches need human approval." >&2
      exit 2
    fi ;;
esac
exit 0
