#!/usr/bin/env bash
# Trimmed from mogger hooks/scripts/lib.sh: only the helpers secret-guard.sh uses (json_fields, json_get, mogger_event).

# json_fields <input> <jq-path>... -> fills the array JF with one value per path ("" when
# missing). One jq call for all of them instead of one per field. Falls back to json_get.
json_fields() {
  local input="$1" filt="" p i=0 out; shift
  JF=()
  if command -v jq >/dev/null 2>&1; then
    for p in "$@"; do filt="$filt${filt:+,}(($p) // \"\" | tostring)"; done
    out=$(printf '%s' "$input" | jq -j "[$filt] | join(\"\\u001f\") + \"\\u001f\"" 2>/dev/null)
    IFS=$'\x1f' read -r -d '' -a JF <<<"$out" || true
    [ "${#JF[@]}" -ge "$#" ] && return 0
    JF=()
  fi
  for p in "$@"; do JF[i]=$(json_get "$input" "$p"); i=$((i + 1)); done
}

# mogger_re <string> <ERE> -> success when the string matches (no fork; honours nocasematch).

json_get() {
  local input="$1" path="$2"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -r "${path} // empty" 2>/dev/null
  elif command -v python3 >/dev/null 2>&1 && python3 -c '1' >/dev/null 2>&1; then
    # the python3 -c '1' probe rejects the Windows Store stub, which
    # exists on PATH but doesn't run anything — just prints an install nag
    printf '%s' "$input" | python3 -c '
import sys, json
path = sys.argv[1].lstrip(".").split(".")
try:
    obj = json.load(sys.stdin)
    for k in path:
        obj = obj[k]
    if obj is None: sys.exit(0)
    print(obj if not isinstance(obj, bool) else str(obj).lower())
except Exception:
    pass
' "$path"
  else
    # Neither tool available — fail open (return empty) rather than block
    # every tool call. session-start.sh warns the user about this.
    printf ''
  fi
}


# mogger_event KIND "short message" — append one line (epoch<TAB>kind<TAB>message)
# to $CLAUDE_PROJECT_DIR/.claude/state/mogger-events.log so a Claude Code mod
# (mods/mogger-status) can show that mogger is working. KIND: block|warn|ok.
# Fail-open: prints nothing, always returns 0. Keep messages short, plain, no
# secrets, no command text: file basenames only. File is capped near 200 lines.
mogger_event() {
  (
    local dir f kind msg n
    dir="${CLAUDE_PROJECT_DIR:-.}/.claude/state"
    f="$dir/mogger-events.log"
    kind=$(printf '%s' "${1:-}" | tr -c 'a-z' '_' | cut -c1-12)
    msg=$(printf '%s' "${2:-}" | tr '\t\r\n' '   ' | tr -d '[:cntrl:]' | cut -c1-120)
    [ -n "$kind" ] && [ -n "$msg" ] || exit 0
    mkdir -p "$dir" || exit 0
    printf '%s\t%s\t%s\n' "$(date +%s)" "$kind" "$msg" >> "$f" || exit 0
    n=$(wc -l < "$f" | tr -d '[:space:]')
    case "$n" in ''|*[!0-9]*) exit 0 ;; esac
    if [ "$n" -gt 240 ]; then
      tail -n 200 "$f" > "$f.$$" && mv "$f.$$" "$f"
      rm -f "$f.$$"
    fi
  ) >/dev/null 2>&1
  return 0
}

# Is this Bash command a test/build/lint run? Shared by fix-loop-guard.sh and
