#!/usr/bin/env bash
# PreToolUse — matcher: Edit|Write
# Safety net for "undo". Before the first edit of a task/turn, takes a
# non-destructive git snapshot of the working tree (tracked + untracked, not
# ignored) under refs/mogger/checkpoints/<timestamp>. It never touches the
# working tree, index, or any branch. Restore with scripts/mogger-rewind.sh
# (see the mogger-rewind skill).
#
# Dedupe: one checkpoint per MOGGER_CHECKPOINT_INTERVAL seconds (default 300),
# OR immediately when the first open task in TASKS.md changes. Identical trees
# are never snapshotted twice. Keeps the newest MOGGER_MAX_CHECKPOINTS (50).
#
# ALWAYS exits 0 — a snapshot problem must never block work. Fails open
# outside git repos. Escape hatch: MOGGER_CHECKPOINT=off.
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/checkpoint-lib.sh"

run() {
  [ "${MOGGER_CHECKPOINT:-on}" = "off" ] && return 0
  cat >/dev/null   # drain stdin; we don't need the payload
  local top gitdir state now last_ts last_task task line
  top=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  gitdir=$(git rev-parse --git-dir 2>/dev/null) || return 0
  cd "$top" || return 0

  line=""
  [ -f TASKS.md ] && line=$(grep -m1 '^[[:space:]]*- \[ \]' TASKS.md 2>/dev/null)
  task=$(printf '%s' "$line" | cksum | cut -d' ' -f1)
  state="$gitdir/mogger-checkpoint-state"
  now=$(date +%s)
  last_ts=0; last_task=""
  if [ -f "$state" ]; then
    read -r last_ts last_task < "$state" 2>/dev/null
    case "$last_ts" in ''|*[!0-9]*) last_ts=0 ;; esac
  fi
  local interval="${MOGGER_CHECKPOINT_INTERVAL:-300}"
  case "$interval" in ''|*[!0-9]*) interval=300 ;; esac
  if [ "$last_ts" -gt 0 ] && [ "$last_task" = "$task" ] && [ $((now - last_ts)) -lt "$interval" ]; then
    return 0
  fi
  local label="before edit"
  [ -n "$line" ] && label="before task: $(printf '%s' "$line" | sed -E 's/^[[:space:]]*- \[ \][[:space:]]*//' | cut -c1-80)"
  [ -n "$(mogger_cp_snapshot "$label" 2>/dev/null)" ] && mogger_event ok "saved a checkpoint"
  printf '%s %s\n' "$now" "$task" > "$state" 2>/dev/null
  return 0
}
run 2>/dev/null
exit 0
