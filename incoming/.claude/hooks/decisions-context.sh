#!/usr/bin/env bash
# Prints ACTIVE decisions from DECISIONS.md, one line each: "#n title — why"
# Newest 20 only, superseded entries skipped, nothing if the file is missing.
# Usage (executed): bash decisions-context.sh [path/to/DECISIONS.md]
# Usage (sourced):  source decisions-context.sh; decisions_context [path]
# Default path: $CLAUDE_PROJECT_DIR/DECISIONS.md, else ./DECISIONS.md.
# Never fails: always returns 0.

decisions_context() {
  local f="${1:-}"
  if [ -z "$f" ]; then f="${CLAUDE_PROJECT_DIR:-.}/DECISIONS.md"; fi
  [ -f "$f" ] || return 0
  awk '
    function flush() {
      if (n != "" && st !~ /^[Ss]uperseded/) {
        line = "#" n " " title
        if (why != "") line = line " — " why
        print line
      }
      n = ""; title = ""; why = ""; st = "active"
    }
    /^<!--/ { if ($0 !~ /-->/) incomment = 1; next }
    incomment { if ($0 ~ /-->/) incomment = 0; next }
    /^## #[0-9]+/ {
      flush()
      h = $0; sub(/^## #/, "", h)
      n = h; sub(/[^0-9].*$/, "", n)
      t = h; sub(/^[0-9]+[ ]*(—|-|:)?[ ]*/, "", t)
      title = t
      next
    }
    n != "" && /^- [Ww]hy:/ && why == "" { w = $0; sub(/^- [Ww]hy:[ ]*/, "", w); why = w; next }
    n != "" && /^- [Ss]tatus:/ { s = $0; sub(/^- [Ss]tatus:[ ]*/, "", s); st = s; next }
    END { flush() }
  ' "$f" 2>/dev/null | tail -n 20
  return 0
}

# Run when executed directly, not when sourced.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  decisions_context "$@"
fi
