#!/usr/bin/env bash
# evals-nudge.sh — SessionStart text for the paid model evals, and the auto-run.
#
# What: prints a short plain-English message (or nothing) and, once the user has
#   agreed to a dollar cap, starts `scripts/mogger-eval.sh run --background` when
#   agents or skills changed. Nothing paid runs without that consent.
# Why: the paid evals show if cheaper models do the work as well. Users should
#   find out they exist (one nudge), agree once, then get results without asking.
#   Nobody is billed without saying yes to a cap.
#
# Rules (all enforced below):
#   - Nudge: at most once per project per MOGGER_NUDGE_DAYS (default 14). Never
#     again after consent or dismissal (.claude/state/evals/nudge.json).
#   - Auto-run needs consent.json with budget_usd > 0. It starts only when the
#     agents/skills fingerprint differs from last.json, or the last run is older
#     than MOGGER_EVAL_MAX_AGE_DAYS (default 30). Never twice in 12 hours, never
#     while running.pid holds a live process, never if the estimate is above the
#     remaining cap (then a "cap too low" note is shown instead).
#   - Never waits for the engine. Never blocks the session. Always exits 0.
#
# State files (all in $CLAUDE_PROJECT_DIR/.claude/state/evals/):
#   nudge.json    {"state":"shown|dismissed|consented","shown_at":EPOCH}  (the skill writes "dismissed")
#   consent.json  {"budget_usd":N,"spent_usd":N}   written by `mogger-eval.sh consent`
#   last.json     {"fingerprint":"...","summary":"..."}   written by the engine
#   running.pid   pid of a live run
#   auto.json     written here: when and for which fingerprint a run started
#   report.md     written by the engine
#
# Escape hatches:
#   MOGGER_EVALS=off          print nothing, start nothing
#   MOGGER_EVAL_BIN=path      use this engine script (tests)
#   MOGGER_NUDGE_DAYS=N       days between nudges (default 14)
#   MOGGER_EVAL_MAX_AGE_DAYS=N  re-run when the last run is older (default 30)
#
# Usage (sourced):   source evals-nudge.sh; evals_session_context
# Usage (executed):  bash evals-nudge.sh
[ -f "$(dirname "${BASH_SOURCE[0]}")/lib.sh" ] && source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

_evn_here() { cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd; }

# Prints the path of the engine script, or nothing.
evals_engine() {
  local c here
  if [ -n "${MOGGER_EVAL_BIN:-}" ]; then
    [ -f "$MOGGER_EVAL_BIN" ] && printf '%s' "$MOGGER_EVAL_BIN"
    return 0
  fi
  here=$(_evn_here)
  for c in "${CLAUDE_PLUGIN_ROOT:-/nonexistent}/scripts/mogger-eval.sh" \
           "$here/../../scripts/mogger-eval.sh" \
           "$here/../scripts/mogger-eval.sh" \
           "$here/mogger-eval.sh"; do
    if [ -f "$c" ]; then printf '%s' "$c"; return 0; fi
  done
  return 0
}

# Reads a number for a JSON key from a file. Empty if absent.
_evn_num() {
  sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\{0,1\}\([0-9][0-9.]*\).*/\1/p' "$1" 2>/dev/null | head -1
}
# Reads a string for a JSON key from a file. Empty if absent.
_evn_str() {
  sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1" 2>/dev/null | head -1
}

# Fingerprint of agent and skill definitions (plugin and project).
evals_fingerprint() {
  local root="${1:-}" p="${CLAUDE_PROJECT_DIR:-.}"
  if [ -z "$root" ]; then root="${CLAUDE_PLUGIN_ROOT:-$(_evn_here)/../..}"; fi
  ( for f in "$root"/agents/*.md "$root"/skills/*/SKILL.md \
             "$p"/.claude/agents/*.md "$p"/.claude/skills/*/SKILL.md; do
      [ -f "$f" ] && { printf '%s\n' "$f"; cat "$f"; }
    done ) 2>/dev/null | cksum | awk '{print $1 "-" $2}'
}

# Runs a command with output to a file, waits at most ~2 seconds. Returns 1 on timeout.
_evn_bounded() {
  local out="$1" pid i=0
  shift
  ( "$@" >"$out" 2>/dev/null </dev/null ) &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    i=$((i + 1))
    if [ "$i" -gt 20 ]; then kill "$pid" 2>/dev/null; return 1; fi
    sleep 0.1
  done
  return 0
}

# First dollar amount in the engine's estimate output, e.g. "1.50". Empty if none.
_evn_estimate() {
  local eng="$1" tmp v
  tmp=$(mktemp 2>/dev/null || mktemp -t mogger) || return 0
  if _evn_bounded "$tmp" bash "$eng" estimate; then
    v=$(grep -Eo '\$[0-9]+(\.[0-9]+)?' "$tmp" 2>/dev/null | head -1 | tr -d '$')
    printf '%s' "$v"
  fi
  rm -f "$tmp"
  return 0
}

_evn_write() {  # _evn_write <file> <content>
  local tmp="$1.tmp.$$"
  { printf '%s\n' "$2" > "$tmp" && mv "$tmp" "$1"; } 2>/dev/null || rm -f "$tmp" 2>/dev/null
  return 0
}

_evn_gt() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a + 0 > b + 0) }'; }

evals_nudge_text() {  # evals_nudge_text <estimate-or-empty>
  echo "## Mogger evals (paid, off until you agree)"
  echo "Mogger can test if cheaper models do your agents' work as well as Sonnet."
  echo "This can cut your bill. The tests call the Claude API, so they cost money."
  if [ -n "$1" ]; then
    echo "Estimated cost: about \$$1 for one run. Nothing runs unless you say yes."
  else
    echo "Cost: run scripts/mogger-eval.sh estimate to see it. Nothing runs unless you say yes."
  fi
  echo "You pick a dollar cap once. After that, tests run by themselves inside the cap."
  echo "Free checks with no cost: scripts/checks/evals-static.sh"
  echo "To hide this message: MOGGER_EVALS=off"
  echo "For Claude: tell the user this in one short paragraph. If they say yes, load skill mogger-evals."
}

evals_session_context() {
  [ "${MOGGER_EVALS:-}" = "off" ] && return 0
  local p="${CLAUDE_PROJECT_DIR:-.}" eng d now days maxage state shown budget spent remaining
  eng=$(evals_engine)
  [ -n "$eng" ] || return 0
  d="$p/.claude/state/evals"
  now=$(date +%s 2>/dev/null) || return 0
  days="${MOGGER_NUDGE_DAYS:-14}"; maxage="${MOGGER_EVAL_MAX_AGE_DAYS:-30}"
  case "$days" in ''|*[!0-9]*) days=14;; esac
  case "$maxage" in ''|*[!0-9]*) maxage=30;; esac

  # Last results: one line when the report is newer than the last session.
  if [ -d "$d" ]; then
    if [ -f "$d/report.md" ] && { [ ! -f "$d/seen" ] || [ "$d/report.md" -nt "$d/seen" ]; }; then
      local sm
      sm=$(_evn_str "$d/last.json" summary | cut -c1-70)
      if [ -n "$sm" ]; then echo "Evals: $sm. See .claude/state/evals/report.md"
      else echo "Evals: new results. See .claude/state/evals/report.md"; fi
    fi
    : > "$d/seen" 2>/dev/null
  fi

  budget=""
  if [ -f "$d/consent.json" ]; then budget=$(_evn_num "$d/consent.json" budget_usd); fi
  if [ -n "$budget" ] && _evn_gt "$budget" 0; then
    # ---- consented: auto-run ----
    if ! grep -q '"consented"' "$d/nudge.json" 2>/dev/null; then
      _evn_write "$d/nudge.json" "{\"state\":\"consented\",\"shown_at\":$now}"
    fi
    # already running?
    if [ -f "$d/running.pid" ]; then
      local rp
      rp=$(tr -dc '0-9' < "$d/running.pid" 2>/dev/null)
      if [ -n "$rp" ] && kill -0 "$rp" 2>/dev/null; then return 0; fi
    fi
    # not twice in 12 hours
    if [ -f "$d/auto.json" ] && [ -n "$(find "$d/auto.json" -mmin -720 2>/dev/null)" ]; then return 0; fi
    # due?
    local fp lastfp autofp ref due=0
    fp=$(evals_fingerprint)
    lastfp=$(_evn_str "$d/last.json" fingerprint)
    autofp=$(_evn_str "$d/auto.json" fingerprint)
    if [ "$fp" != "$lastfp" ] && [ "$fp" != "$autofp" ]; then due=1; fi
    ref=""
    if [ -f "$d/last.json" ]; then ref="$d/last.json"; elif [ -f "$d/auto.json" ]; then ref="$d/auto.json"; fi
    if [ -n "$ref" ] && [ -n "$(find "$ref" -mtime +"$maxage" 2>/dev/null)" ]; then due=1; fi
    [ "$due" -eq 1 ] || return 0
    # inside the cap?
    local est
    est=$(_evn_estimate "$eng")
    [ -n "$est" ] || return 0
    spent=$(_evn_num "$d/consent.json" spent_usd); spent="${spent:-0}"
    remaining=$(awk -v b="$budget" -v s="$spent" 'BEGIN { r = b - s; if (r < 0) r = 0; printf "%.2f", r }')
    if _evn_gt "$est" "$remaining"; then
      # cap too low: nudge at most once per window
      local cn=0
      if [ -f "$d/cap-nudge.txt" ]; then
        cn=$(tr -dc '0-9' < "$d/cap-nudge.txt" 2>/dev/null); cn="${cn:-0}"
      fi
      if [ $((now - cn)) -ge $((days * 86400)) ]; then
        echo "Evals: cap too low. The next run needs about \$$est. Left in your cap: \$$remaining."
        echo "To raise the cap, ask me: \"raise the evals cap\"."
        _evn_write "$d/cap-nudge.txt" "$now"
      fi
      return 0
    fi
    # start one background run; never wait for it
    _evn_write "$d/auto.json" "{\"launched_at\":$now,\"fingerprint\":\"$fp\"}"
    ( bash "$eng" run --background --budget "$remaining" >/dev/null 2>&1 </dev/null & ) 2>/dev/null
    echo "Evals: started a background run. Estimated cost \$$est. Cap left \$$remaining."
    echo "Results will be in .claude/state/evals/report.md"
    return 0
  fi

  # ---- not consented: nudge at most once per window ----
  state=""; shown=0
  if [ -f "$d/nudge.json" ]; then
    state=$(_evn_str "$d/nudge.json" state)
    shown=$(_evn_num "$d/nudge.json" shown_at); shown="${shown:-0}"
  fi
  case "$state" in dismissed|consented) return 0;; esac
  if [ "$state" = "shown" ] && [ $((now - shown)) -lt $((days * 86400)) ]; then return 0; fi
  local est2
  est2=$(_evn_estimate "$eng")
  mkdir -p "$d" 2>/dev/null || return 0
  _evn_write "$d/nudge.json" "{\"state\":\"shown\",\"shown_at\":$now}"
  evals_nudge_text "$est2"
  return 0
}

# Run when executed directly, not when sourced.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  evals_session_context "$@" 2>/dev/null
  exit 0
fi
