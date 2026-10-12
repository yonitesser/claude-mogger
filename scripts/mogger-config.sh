#!/usr/bin/env bash
# List and flip mogger guards. State lives in $CLAUDE_PROJECT_DIR/.claude/mogger.json.
#   mogger-config.sh list            every guard: state, kind, what ON and OFF do
#   mogger-config.sh set NAME on|off [--confirm]
#   mogger-config.sh reset NAME|all  back to default
# Turning a safety guard off needs --confirm (exit 3 with a warning without it).
# An env var that is set still wins over the file; list shows "env".
set -u
ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
CAT="$ROOT/hooks/guards.tsv"; [ -f "$CAT" ] || CAT="$ROOT/.claude/guards.tsv"
CFG="${CLAUDE_PROJECT_DIR:-.}/.claude/mogger.json"
command -v jq >/dev/null 2>&1 || { echo "mogger-config needs jq" >&2; exit 2; }
[ -f "$CAT" ] || { echo "guard list not found: $CAT" >&2; exit 2; }
rows() { grep -v '^#' "$CAT"; }
row() { rows | awk -F'\t' -v n="$1" '$1==n'; }
cur() { [ -f "$CFG" ] && jq -r --arg k "$1" '.[$k] // empty' "$CFG" 2>/dev/null; }
write() {  # write <jq filter> [jq args...]
  local f="$1"; shift; mkdir -p "$(dirname "$CFG")"
  [ -f "$CFG" ] || echo '{}' > "$CFG"
  jq "$@" "$f" "$CFG" > "$CFG.tmp" && mv "$CFG.tmp" "$CFG"
}
case "${1:-list}" in
  list)
    printf '%s\n' "name | state | kind | ON does | OFF does"
    rows | while IFS=$'\t' read -r n e kind onv dflt on_t off_t; do
      st="$dflt"; src=default
      v=$(cur "$n"); [ -n "$v" ] && { st="$v"; src=file; }
      if [ -n "${!e+x}" ]; then
        case "${!e}" in off) st=off ;; *) st=on ;; esac; src=env
      fi
      printf '%s | %s (%s) | %s | %s | %s\n' "$n" "$st" "$src" "$kind" "$on_t" "$off_t"
    done ;;
  set)
    n="${2:-}"; v="${3:-}"
    r=$(row "$n"); [ -n "$r" ] || { echo "unknown guard: $n (run: list)" >&2; exit 1; }
    case "$v" in on|off) ;; *) echo "value must be on or off" >&2; exit 1 ;; esac
    kind=$(printf '%s' "$r" | cut -f3); off_t=$(printf '%s' "$r" | cut -f7)
    if [ "$v" = off ] && [ "$kind" = safety ] && [ "${4:-}" != "--confirm" ]; then
      echo "WARNING: $n is a safety guard. If you turn it off: $off_t" >&2
      echo "Ask the user. If they agree, run again with --confirm." >&2
      exit 3
    fi
    write '.[$k]=$v' --arg k "$n" --arg v "$v" || exit 1
    echo "$n = $v (saved in $CFG). Takes effect on the next tool call." ;;
  reset)
    n="${2:-}"
    if [ "$n" = all ]; then rm -f "$CFG"; echo "all guards back to default"
    else
      [ -n "$(row "$n")" ] || { echo "unknown guard: $n" >&2; exit 1; }
      [ -f "$CFG" ] && write 'del(.[$k])' --arg k "$n"
      echo "$n back to default"
    fi ;;
  *) echo "usage: mogger-config.sh list | set NAME on|off [--confirm] | reset NAME|all" >&2; exit 1 ;;
esac
