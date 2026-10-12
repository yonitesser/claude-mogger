#!/usr/bin/env bash
# List and flip mogger guards. State lives in $CLAUDE_PROJECT_DIR/.claude/mogger.json.
#   mogger-config.sh list            every guard: state, kind, what ON and OFF do
#   mogger-config.sh set NAME on|ask|off [--confirm]
#     on = block, ask = permission prompt for the human each time, off = allow.
#     Only guards that can ask accept ask (the list shows each guard's states).
#   mogger-config.sh reset NAME|all  back to default
# Turning a safety guard off needs --confirm (exit 3 with a warning without it).
# Turning one to ask needs no confirm: a human still decides each time.
# An env var that is set still wins over the file; list shows "env".
set -u
ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
CAT="$ROOT/hooks/guards.tsv"; [ -f "$CAT" ] || CAT="$ROOT/.claude/guards.tsv"
CFG="${CLAUDE_PROJECT_DIR:-.}/.claude/mogger.json"
command -v jq >/dev/null 2>&1 || { echo "mogger:config needs jq" >&2; exit 2; }
[ -f "$CAT" ] || { echo "guard list not found: $CAT" >&2; exit 2; }
rows() { grep -v '^#' "$CAT"; }
row() { rows | awk -F'\t' -v n="$1" '$1==n'; }
has() { case ",$1," in *",$2,"*) return 0 ;; esac; return 1; }  # has <csv> <item>
cur() { [ -f "$CFG" ] && jq -r --arg k "$1" '.[$k] // empty' "$CFG" 2>/dev/null; }
write() {  # write <jq filter> [jq args...]
  local f="$1"; shift; mkdir -p "$(dirname "$CFG")"
  [ -f "$CFG" ] || echo '{}' > "$CFG"
  jq "$@" "$f" "$CFG" > "$CFG.tmp" && mv "$CFG.tmp" "$CFG"
}
case "${1:-list}" in
  list)
    printf '%s\n' "name | state | kind | allowed | ON does | ASK does | OFF does"
    rows | while IFS=$'\t' read -r n e kind onv dflt on_t off_t states ask_t; do
      states="${states:-on,off}"; st="$dflt"; src=default
      v=$(cur "$n"); [ -n "$v" ] && has "$states" "$v" && { st="$v"; src=file; }
      if [ -n "${!e+x}" ]; then
        case "${!e}" in
          off) st=off ;;
          ask) if has "$states" ask; then st=ask; else st="$onv"; fi ;;
          *) st="$onv" ;;
        esac
        [ "$st" = "$onv" ] && [ "$onv" != ask ] && st=on
        src=env
      fi
      printf '%s | %s (%s) | %s | %s | %s | %s | %s\n' "$n" "$st" "$src" "$kind" "$states" "$on_t" "${ask_t:--}" "$off_t"
    done ;;
  set)
    n="${2:-}"; v="${3:-}"
    r=$(row "$n"); [ -n "$r" ] || { echo "unknown guard: $n (run: list)" >&2; exit 1; }
    case "$v" in on|ask|off) ;; *) echo "value must be on, ask or off" >&2; exit 1 ;; esac
    states=$(printf '%s' "$r" | cut -f8); states="${states:-on,off}"
    has "$states" "$v" || { echo "$n cannot be $v. Allowed: $states" >&2; exit 1; }
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
  *) echo "usage: mogger-config.sh list | set NAME on|ask|off [--confirm] | reset NAME|all" >&2; exit 1 ;;
esac
