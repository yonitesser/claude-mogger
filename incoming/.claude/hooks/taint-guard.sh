#!/usr/bin/env bash
# PreToolUse — matcher: Bash
# After outside content was read (taint-mark.sh), ask the human before a command
# that sends data over the network or changes where code goes: curl, wget, nc,
# scp, rsync, ssh, ftp, git remote add/set-url. Localhost is not asked about.
# Asks (never blocks), once per command. Speed bump against prompt injection,
# not a defence: a determined attacker can phrase around it.
# Env: MOGGER_TAINT=off disables. MOGGER_TAINT_TTL=seconds (default 7200).
source "${0%/*}/lib.sh"
[ "${MOGGER_TAINT:-on}" = "off" ] && exit 0
F="${CLAUDE_PROJECT_DIR:-.}/.claude/state/tainted"
[ -f "$F" ] || exit 0
INPUT=$(cat)
CMD=$(json_get "$INPUT" '.tool_input.command'); [ -n "$CMD" ] || exit 0

TS=$(cut -f1 "$F" 2>/dev/null); SRC=$(cut -f2 "$F" 2>/dev/null)
case "$TS" in ''|*[!0-9]*) exit 0 ;; esac
[ $(( $(date +%s) - TS )) -gt "${MOGGER_TAINT_TTL:-7200}" ] && exit 0

CLEAN=$(printf '%s' "$CMD" | tr -d "\"'\`")
EGRESS='(^|[;&|(]|[[:space:]])(curl|wget|nc|ncat|netcat|socat|scp|sftp|rsync|ssh|ftp|telnet)[[:space:]]|git[[:space:]]+([^;&|]*[[:space:]])?remote[[:space:]]+(add|set-url)'
printf '%s' "$CLEAN" | grep -qE "$EGRESS" || exit 0
# local-only traffic is fine: judge URL hosts when there are any, else the bare words (`nc localhost 80`)
LOCAL='(localhost|127\.0\.0\.1|\[::1\]|0\.0\.0\.0)'
HOSTS=$(printf '%s' "$CLEAN" | grep -oE '[A-Za-z][A-Za-z0-9+.-]*://[^/[:space:]]+' | sed -E 's#^[^:]*://([^@]*@)?##')
if [ -n "$HOSTS" ]; then
  printf '%s\n' "$HOSTS" | grep -qvE "^$LOCAL(:[0-9]+)?$" || exit 0
else
  printf '%s' "$CLEAN" | grep -qE "$LOCAL" && exit 0
fi

mogger_event warn "asked before a network command after reading outside content"
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"This session read outside content (%s), which can carry hidden instructions. Approve this network command only if you asked for it."}}\n' "${SRC:-web}"
exit 0
