#!/usr/bin/env bash
# PreToolUse — matcher: mcp__github__merge_pull_request, push_files, ... (see hooks.json)
# The Bash gate (require-approval.sh) cannot see GitHub tools that Claude calls
# through MCP. This one covers them with the same rules:
#   merging a PR, enabling auto-merge, deleting a repo/file: always blocked.
#   push_files / create_or_update_file / delete_file (they commit straight to a
#   branch): blocked unless MOGGER_ALLOW_PUSH=on, and never on a protected branch.
# Tool names are matched on the part after the last "__", so other servers with
# the same tool names (github enterprise, gitlab-style names) are covered too.
# Same states as the Bash gate: MOGGER_PUSH_GUARD and MOGGER_MERGE_GUARD, each
# on (block), ask (permission prompt for the human) or off (allow; merge has no
# off). Where no prompt can be shown, ask blocks.
source "$(dirname "$0")/lib.sh"

INPUT=$(cat)
TOOL=$(json_get "$INPUT" '.tool_name')
[ -n "$TOOL" ] || exit 0
NAME="${TOOL##*__}"

PUSH=$(mogger_state MOGGER_PUSH_GUARD on)
[ "${MOGGER_ALLOW_PUSH:-off}" = "on" ] && [ "$PUSH" = on ] && PUSH=off
MERGE=$(mogger_state MOGGER_MERGE_GUARD on); [ "$MERGE" = off ] && MERGE=on

# ask_or_block <event> <block message> <ask reason>: the ask state; exits.
ask_or_block() {
  if mogger_can_ask "$INPUT"; then
    mogger_event warn "asked before $1"; mogger_ask_json "$3"; exit 0
  fi
  mogger_event block "$1"; echo "BLOCKED: $2 (Ask mode is on, but this session cannot show a prompt, so it is blocked.)" >&2
  exit 2
}

case "$NAME" in
  merge_pull_request|enable_pr_auto_merge|delete_repository|delete_branch)
    [ "$MERGE" = ask ] && ask_or_block "MCP $NAME" "$NAME merges or deletes on GitHub and needs human approval. Report that the work is ready and stop." "Mogger: $NAME merges or deletes on GitHub. Approve only if you want that."
    mogger_event block "blocked MCP $NAME"; echo "BLOCKED: $NAME merges or deletes on GitHub and needs human approval. Report that the work is ready and stop." >&2
    exit 2 ;;
  push_files|create_or_update_file|delete_file)
    if [ "$PUSH" = on ]; then
      mogger_event block "blocked MCP $NAME"; echo "BLOCKED: $NAME commits straight to a remote branch and needs human approval. Do not retry with another tool." >&2
      exit 2
    fi
    BR=$(json_get "$INPUT" '.tool_input.branch')
    if [ -z "$BR" ] || is_protected_branch "${BR#refs/heads/}"; then
      mogger_event block "blocked MCP $NAME on a protected or unnamed branch"; echo "BLOCKED: $NAME needs an explicit feature branch (got '${BR:-none}'). Protected branches need human approval." >&2
      exit 2
    fi
    [ "$PUSH" = ask ] && ask_or_block "MCP $NAME" "$NAME commits straight to a remote branch and needs human approval." "Mogger: $NAME commits straight to branch ${BR#refs/heads/}. Approve only if you want that." ;;
esac
exit 0
