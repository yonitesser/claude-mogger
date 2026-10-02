#!/usr/bin/env bash
# Sourced by every hook. Provides json_get so hooks work with jq OR python3.
# Usage: VALUE=$(json_get "$INPUT" '.tool_input.file_path')

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

# Current git branch, empty if not in a repo
git_branch() {
  git rev-parse --abbrev-ref HEAD 2>/dev/null || printf ''
}

# Is this branch one we treat as protected? Override with MOGGER_PROTECTED_BRANCHES="main|master|prod|release/.*"
is_protected_branch() {
  local b="$1" pat="${MOGGER_PROTECTED_BRANCHES:-main|master|prod|production|release/.*}"
  [[ "$b" =~ ^($pat)$ ]]
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
