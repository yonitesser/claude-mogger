#!/usr/bin/env bash
# PostToolUse - matcher: Edit|Write
# Parses the file Claude just wrote and warns on a SYNTAX error right away, so it is not
# found twenty edits later. Python (ast, no .pyc written), shell (bash -n), JSON, JavaScript
# (node --check). Costs no model tokens: silent when the file parses. WARN only
# (additionalContext, exit 0): a multi-step edit can be briefly broken on purpose.
# Skipped: files over 400 KB, vendor/build dirs, JSON that allows comments (tsconfig,
# .jsonc, .vscode), missing parsers. Fails OPEN on anything unexpected.
# Escape hatch: MOGGER_CHECK_SYNTAX=off

source "${0%/*}/lib.sh"
[ "${MOGGER_CHECK_SYNTAX:-on}" = "off" ] && exit 0

INPUT=$(cat)
FILE=$(json_get "$INPUT" '.tool_input.file_path')
[ -n "$FILE" ] && [ -f "$FILE" ] || exit 0

case "$FILE" in
  *.py|*.sh|*.bash|*.json|*.js|*.mjs|*.cjs) ;;
  *) exit 0 ;;
esac
case "/$FILE" in */node_modules/*|*/.git/*|*/dist/*|*/build/*|*/venv/*|*/.venv/*|*/.vscode/*|*/vendor/*) exit 0 ;; esac
BASE=${FILE##*/}
case "$BASE" in tsconfig*.json|jsconfig*.json|*.jsonc|*.min.js|*.min.mjs) exit 0 ;; esac
SZ=$(wc -c < "$FILE" 2>/dev/null); SZ=${SZ//[[:space:]]/}
[ -n "$SZ" ] && [ "$SZ" -gt 400000 ] && exit 0

ERR=""
case "$FILE" in
  *.py)
    command -v python3 >/dev/null 2>&1 || exit 0
    ERR=$(python3 -c 'import ast,sys; ast.parse(open(sys.argv[1],"rb").read(), sys.argv[1])' "$FILE" 2>&1 >/dev/null | tail -3) ;;
  *.sh|*.bash)
    ERR=$(bash -n "$FILE" 2>&1 | head -3) ;;
  *.json)
    command -v jq >/dev/null 2>&1 || exit 0
    ERR=$(jq empty "$FILE" 2>&1 >/dev/null | head -2) ;;
  *.js|*.mjs|*.cjs)
    command -v node >/dev/null 2>&1 || exit 0
    ERR=$(node --check "$FILE" 2>&1 >/dev/null | head -6) ;;
esac
[ -z "$ERR" ] && exit 0

MSG="Syntax error in $FILE (found by a parser, not a guess): $(printf '%s' "$ERR" | tr '\n' ' ' | cut -c1-400) Fix it before the next edit."
mogger_event warn "syntax error in ${FILE##*/}"
MSG=${MSG//\\/\\\\}; MSG=${MSG//\"/\\\"}; MSG=${MSG//$'\t'/ }
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' "$MSG"
exit 0
