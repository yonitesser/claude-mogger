#!/usr/bin/env bash
# PreToolUse — matcher: Edit|Write
# Bookkeeping for two quality checks, no git needed, no model tokens:
#  - the FIRST time a test file is about to be edited, copy its current content
#    to .claude/state/test-baseline/ (check-test-tamper.sh compares against it)
#  - log every code/test edit to .claude/state/edits.log (stop-tests-added.sh
#    reads it at the end of the turn)
# Always exits 0; fails open on anything odd. Escape hatch: MOGGER_TRACK_EDITS=off
[ "${MOGGER_TRACK_EDITS:-on}" = "off" ] && exit 0
MOGGER_TQ_SOURCE_ONLY=1 source "$(dirname "$0")/check-test-quality.sh" 2>/dev/null
source "$(dirname "$0")/lib.sh"

INPUT=$(cat)
FP=$(json_get "$INPUT" '.tool_input.file_path')
[ -n "$FP" ] || exit 0
REL="$FP"
case "$FP" in "$PWD"/*) REL="${FP#"$PWD"/}" ;; esac
case "$REL" in /*|../*) exit 0 ;; esac
STATE=".claude/state"
mkdir -p "$STATE/test-baseline" 2>/dev/null || exit 0

if tq_is_test_path "$REL"; then
  KEY=$(printf '%s' "$REL" | cksum | cut -d' ' -f1)
  [ -f "$FP" ] && [ ! -e "$STATE/test-baseline/$KEY" ] && cp "$FP" "$STATE/test-baseline/$KEY" 2>/dev/null
  printf 'T %s\n' "$REL" >> "$STATE/edits.log" 2>/dev/null
  exit 0
fi
case "${REL##*.}" in
  py|js|jsx|ts|tsx|mjs|cjs|go|rs|java|rb|php|kt|swift|cs)
    case "$REL" in node_modules/*|*/node_modules/*|dist/*|build/*|vendor/*|docs/*|scripts/*|migrations/*) exit 0 ;; esac
    printf 'C %s\n' "$REL" >> "$STATE/edits.log" 2>/dev/null ;;
esac
exit 0
