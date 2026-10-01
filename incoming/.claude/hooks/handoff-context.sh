#!/usr/bin/env bash
# Prints .claude/state/handoff.md (written by precompact-save.sh) for
# SessionStart, prefixed with its age, capped at 60 lines.
# Prints NOTHING when the file is missing, empty, or older than
# MOGGER_HANDOFF_MAX_AGE_HOURS (default 72): a stale handoff misleads.
# Usage (executed): bash handoff-context.sh [path/to/handoff.md]
# Usage (sourced):  source handoff-context.sh; handoff_context [path]
# Default path: $CLAUDE_PROJECT_DIR/.claude/state/handoff.md, else ./.claude/state/handoff.md
# Never fails: always returns 0.

handoff_context() {
  local f="${1:-}" max now mt age_s age_h age_txt
  if [ -z "$f" ]; then f="${CLAUDE_PROJECT_DIR:-.}/.claude/state/handoff.md"; fi
  [ -s "$f" ] || return 0
  max="${MOGGER_HANDOFF_MAX_AGE_HOURS:-72}"
  case "$max" in ''|*[!0-9]*) max=72 ;; esac
  now=$(date +%s 2>/dev/null) || return 0
  mt=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null) || return 0
  case "$mt" in ''|*[!0-9]*) return 0 ;; esac
  age_s=$((now - mt)); [ "$age_s" -lt 0 ] && age_s=0
  age_h=$((age_s / 3600))
  [ "$age_h" -gt "$max" ] && return 0
  if [ "$age_s" -lt 3600 ]; then age_txt="$((age_s / 60)) min"; else age_txt="${age_h} h"; fi
  echo "Handoff saved ${age_txt} ago (facts captured before the last compaction; re-verify before relying on them):"
  head -n 60 "$f" 2>/dev/null
  if [ "$(wc -l < "$f" 2>/dev/null | tr -d ' ')" -gt 60 ]; then echo "... (truncated; full file: .claude/state/handoff.md)"; fi
  return 0
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  handoff_context "$@"
fi
