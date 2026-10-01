#!/usr/bin/env bash
# PreCompact (matcher: manual|auto; register with no matcher to cover both)
#
# WHAT: just before the conversation is compacted (and details are lost),
# write .claude/state/handoff.md, a short note built ONLY from facts read
# from the project: TASKS.md counts and next tasks, BLOCKED lines, git status
# and log, the latest mogger checkpoint, the test and smoke markers, active
# DECISIONS.md lines, UNVERIFIED assumptions, and open review notes.
# It never copies transcript text, so nothing in it is guessed or invented.
# handoff-context.sh prints it back at the next SessionStart (source
# compact/resume/startup) so the AI does not forget the earlier work.
#
# WHY: long sessions get compacted; the AI then forgets earlier decisions and
# new code breaks old code. The handoff is the memory that survives.
#
# Guarantees: ALWAYS exits 0 (never blocks compaction), prints nothing to
# stdout, atomic write (temp file + mv), fails OPEN when jq/python3 or git
# are missing, garbage stdin is ignored. No python, so it is fast.
# Escape hatch: MOGGER_HANDOFF=off disables it. Output file is git-ignored
# territory (.claude/state/); it is not committed by this hook.
source "$(dirname "$0")/lib.sh" 2>/dev/null
HOOKDIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"

INPUT=""
[ -t 0 ] || INPUT=$(cat 2>/dev/null)

_mtime() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || printf 0
}
_fmt() {
  date -u -d "@$1" +"%Y-%m-%d %H:%M:%SZ" 2>/dev/null || date -u -r "$1" +"%Y-%m-%d %H:%M:%SZ" 2>/dev/null || printf '%s' "$1"
}

build_handoff() {
  local trig n_done n_open st nxt blk
  trig=$(json_get "$INPUT" '.trigger' 2>/dev/null)
  case "$trig" in manual|auto) ;; *) trig="" ;; esac

  echo "# Handoff (auto-saved before compaction)"
  echo
  echo "_Built by mogger precompact-save.sh from repo and state files only. Nothing here comes from the chat. Re-verify before relying on it._"
  echo "- saved: $(date -u +"%Y-%m-%d %H:%M:%SZ")${trig:+ (compaction: $trig)}"

  echo
  echo "## Tasks (TASKS.md)"
  if [ -f TASKS.md ]; then
    n_done=$(grep -c '^[[:space:]]*- \[[xX]\]' TASKS.md 2>/dev/null); n_done=${n_done:-0}
    n_open=$(grep -c '^[[:space:]]*- \[ \]' TASKS.md 2>/dev/null); n_open=${n_open:-0}
    echo "- $n_done done, $n_open open"
    st=$(grep -m1 -iE '^##[[:space:]]+Status:' TASKS.md 2>/dev/null)
    [ -n "$st" ] && echo "- ${st#\#\# }"
    nxt=$(grep -E '^[[:space:]]*- \[ \]' TASKS.md 2>/dev/null | head -3 | sed 's/^[[:space:]]*- \[ \] //')
    if [ -n "$nxt" ]; then echo "- next open:"; printf '%s\n' "$nxt" | sed 's/^/  - /'; fi
    blk=$(grep -iE '^[[:space:]]*(- )?BLOCKED:' TASKS.md 2>/dev/null | sed 's/^[[:space:]]*//' | head -5)
    if [ -n "$blk" ]; then echo "- blocked:"; printf '%s\n' "$blk" | sed 's/^/  - /'; fi
  else
    echo "- no TASKS.md"
  fi

  echo
  echo "## Git"
  if git rev-parse --git-dir >/dev/null 2>&1; then
    local br files nfiles log cp
    br=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    echo "- branch: ${br:-unknown}"
    files=$(git status --porcelain 2>/dev/null | grep -v -E '^.. \.claude/' | head -15)
    nfiles=$(git status --porcelain 2>/dev/null | grep -v -E '^.. \.claude/' | wc -l | tr -d ' ')
    if [ -n "$files" ]; then
      echo "- files touched, uncommitted ($nfiles):"
      printf '%s\n' "$files" | sed 's/^/  - /'
    else
      echo "- working tree clean"
    fi
    log=$(git log -5 --oneline 2>/dev/null)
    if [ -n "$log" ]; then echo "- last 5 commits:"; printf '%s\n' "$log" | sed 's/^/  - /'
    else echo "- no commits yet"; fi
    if [ -f "$HOOKDIR/checkpoint-lib.sh" ]; then
      source "$HOOKDIR/checkpoint-lib.sh" 2>/dev/null
      cp=$(mogger_cp_latest 2>/dev/null)
      if [ -n "$cp" ]; then echo "- last checkpoint: ${cp##*/} (restore with scripts/mogger-rewind.sh)"
      else echo "- no mogger checkpoint yet"; fi
    fi
  else
    echo "- not a git repository (no version control: nothing can be rolled back)"
  fi

  echo
  echo "## Test and smoke markers"
  local M=.claude/state/last_test_result.json S=.claude/state/smoke.json
  if [ -f "$M" ]; then
    echo "- tests: status '$(json_get "$(cat "$M")" '.status')' scope '$(json_get "$(cat "$M")" '.scope')' recorded $(_fmt "$(_mtime "$M")")"
  else
    echo "- tests: no recorded run"
  fi
  if [ -f "$S" ]; then
    echo "- smoke: ok=$(json_get "$(cat "$S")" '.ok') url '$(json_get "$(cat "$S")" '.url')' status '$(json_get "$(cat "$S")" '.status')' recorded $(_fmt "$(_mtime "$S")")"
  else
    echo "- smoke: no recorded run"
  fi

  if [ -f DECISIONS.md ] && [ -f "$HOOKDIR/decisions-context.sh" ]; then
    local dec
    source "$HOOKDIR/decisions-context.sh" 2>/dev/null
    dec=$(decisions_context DECISIONS.md 2>/dev/null)
    if [ -n "$dec" ]; then
      echo
      echo "## Active decisions (DECISIONS.md)"
      printf '%s\n' "$dec" | sed 's/^/- /'
    fi
  fi

  local unv=""
  unv=$(cat TASKS.md SPEC.md 2>/dev/null | grep -E 'UNVERIFIED:' | grep -v -E 'UNVERIFIED:[[:space:]]*<' | sed 's/^[[:space:]]*//' | head -10)
  if [ -n "$unv" ]; then
    echo
    echo "## Unverified assumptions (TASKS.md / SPEC.md)"
    printf '%s\n' "$unv" | sed 's/^/- /; s/^- - /- /'
  fi

  local rv="" rf
  for rf in .claude/state/review.md .claude/state/review-notes.md REVIEW.md; do
    [ -f "$rf" ] || continue
    rv="$rv$(grep -E 'NOT READY|^[[:space:]]*- \[ \]' "$rf" 2>/dev/null | sed 's/^[[:space:]]*//' | head -5)
"
  done
  rv=$(printf '%s' "$rv" | sed '/^$/d' | head -5)
  if [ -n "$rv" ]; then
    echo
    echo "## Open review notes"
    printf '%s\n' "$rv" | sed 's/^/- /; s/^- - /- /'
  fi
}

main() {
  [ "${MOGGER_HANDOFF:-on}" = "off" ] && return 0
  cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || return 0
  # Only write in a project that has something to report.
  if [ ! -f TASKS.md ] && ! git rev-parse --git-dir >/dev/null 2>&1; then return 0; fi
  local body tmp
  body=$(build_handoff) || return 0
  [ -n "$body" ] || return 0
  mkdir -p .claude/state 2>/dev/null || return 0
  tmp=".claude/state/handoff.md.tmp.$$"
  printf '%s\n' "$body" > "$tmp" 2>/dev/null && mv -f "$tmp" .claude/state/handoff.md 2>/dev/null
  rm -f "$tmp" 2>/dev/null
  return 0
}

main >/dev/null 2>&1 || true
exit 0
