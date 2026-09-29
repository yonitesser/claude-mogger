#!/usr/bin/env bash
# PostToolUse hook — matches: Edit|Write
# Blocks ONE thing, and only when it is unambiguous: silently swallowed errors
# in the code that was just written:
#   JS/TS:   catch (e) {}   /   catch {}   /   .catch(() => {})
#   Python:  except: pass   /   except Exception: pass   /   except BaseException: pass
# (JS: any empty catch. Python: bare except and Exception/BaseException only;
#  narrow ones such as `except KeyError: pass` are normal and are left alone.)
# An empty error handler is how apps end up "down and nobody knows": log it,
# handle it, or re-throw it.
# An intentional swallow is allowed when it carries a reason marker on the same
# or previous line, e.g.   // ignore: cache is best-effort   /   # ignore: ...
# For Edit the check runs on the new_string only, so pre-existing code in a big
# file never blocks an unrelated edit; for Write it runs on the whole file.
# Skips: tests, mocks, fixtures, generated/minified files, vendored dirs.
# Escape hatch: MOGGER_CHECK_RESILIENCE=off. Fails open without jq/python3.
# The broader, heuristic resilience audit lives in scripts/checks/resilience.sh.

source "$(dirname "$0")/lib.sh"
[ "${MOGGER_CHECK_RESILIENCE:-on}" = "off" ] && exit 0

INPUT=$(cat)
FILE_PATH=$(json_get "$INPUT" '.tool_input.file_path')
[ -z "$FILE_PATH" ] && exit 0
[ -f "$FILE_PATH" ] || exit 0

EXT="${FILE_PATH##*.}"
case "$EXT" in
  js|jsx|mjs|cjs|ts|tsx|py) ;;
  *) exit 0 ;;
esac
case "$FILE_PATH" in
  */node_modules/*|*/dist/*|*/build/*|*/vendor/*|*/.git/*|*/venv/*|*/.venv/*|*/site-packages/*|*/.next/*|*/__pycache__/*) exit 0 ;;
  *.min.*|*.bundle.js|*.d.ts|*.generated.*|*_generated.*|*.gen.*|*_pb2.py|*/generated/*|*/__generated__/*) exit 0 ;;
  *.test.*|*.spec.*|*/__tests__/*|*/tests/*|*/test/*|*/test_*|test_*|*_test.py|*/conftest.py|*/fixtures/*|*/mocks/*|*/__mocks__/*|*/e2e/*) exit 0 ;;
esac

TMP=$(mktemp -d 2>/dev/null || mktemp -d -t mogger-cr) || exit 0
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/swallow.awk" <<'EOF'
function isc(s) { return (s ~ /^[[:space:]]*(\/\/|#|\*|\/\*)/) }
function rep(ln, what) { printf "%d: %s\n", ln + OFF, what }
function pyproc(line) {
  if (pend) {
    if (line ~ /^[[:space:]]*$/) return
    if (line ~ /^[[:space:]]*#/) { if (line ~ /ignore:/) pdoc=1; return }
    if (line ~ /^[[:space:]]*(pass|[.][.][.])[[:space:]]*(#.*)?$/) { if (!pdoc && line !~ /ignore:/) rep(pln, "except block only does pass") }
    pend=0
  }
  if (line ~ /^[[:space:]]*except[[:space:]]*(Exception|BaseException)?([[:space:]]+as[[:space:]]+[[:alnum:]_]+)?[[:space:]]*:[[:space:]]*(pass|[.][.][.])[[:space:]]*(#.*)?$/) {
    if (line !~ /ignore:/ && prev !~ /ignore:/) rep(FNR, "except: pass swallows the error")
  } else if (line ~ /^[[:space:]]*except[[:space:]]*(Exception|BaseException)?([[:space:]]+as[[:space:]]+[[:alnum:]_]+)?[[:space:]]*:[[:space:]]*(#.*)?$/) {
    pend=1; pln=FNR; pdoc=(line ~ /ignore:/ || prev ~ /ignore:/)
  }
}
function jsproc(line) {
  if (line ~ /^[[:space:]]*$/) return
  if (isc(line)) { jpend=0; return }
  if (jpend) { if (line ~ /^[[:space:]]*[}]/) rep(jln, "empty catch block"); jpend=0 }
  if (line ~ /catch[[:space:]]*([(][^)]*[)])?[[:space:]]*[{][[:space:]]*[}]/) {
    if (line !~ /ignore:/ && prev !~ /ignore:/) rep(FNR, "empty catch block")
  } else if (line ~ /catch[[:space:]]*([(][^)]*[)])?[[:space:]]*[{][[:space:]]*$/) {
    if (line !~ /ignore:/ && prev !~ /ignore:/) { jpend=1; jln=FNR }
  }
  if (line ~ /[.]catch[(][[:space:]]*(async[[:space:]]*)?([(][^)]*[)]|[[:alnum:]_$]+)[[:space:]]*=>[[:space:]]*[{][[:space:]]*[}][[:space:]]*[)]/ ||
      line ~ /[.]catch[(][[:space:]]*function[[:space:]]*[(][^)]*[)][[:space:]]*[{][[:space:]]*[}][[:space:]]*[)]/) {
    if (line !~ /ignore:/ && prev !~ /ignore:/) rep(FNR, ".catch(() => {}) swallows the error")
  }
}
{ if (EXT=="py") pyproc($0); else jsproc($0); prev=$0 }
EOF

TARGET="$FILE_PATH"; OFF=0
NEWS=$(json_get "$INPUT" '.tool_input.new_string')
if [ -n "$NEWS" ]; then
  # Edit: only the text the model just wrote. Map lines back to the file.
  printf '%s\n' "$NEWS" > "$TMP/new"
  TARGET="$TMP/new"
  FIRST=$(printf '%s\n' "$NEWS" | head -1)
  if [ -n "$FIRST" ]; then
    LN=$(grep -n -F -m1 -- "$FIRST" "$FILE_PATH" 2>/dev/null | cut -d: -f1)
    [ -n "$LN" ] && OFF=$((LN-1))
  fi
fi

HITS=$(awk -v EXT="$EXT" -v OFF="$OFF" -f "$TMP/swallow.awk" "$TARGET" 2>/dev/null | head -5)
if [ -n "$HITS" ]; then
  {
    echo "BLOCKED: $FILE_PATH swallows errors silently:"
    printf '%s\n' "$HITS" | sed "s|^|  $FILE_PATH:|"
    echo "An empty catch/except hides failures until a customer reports them. Do one of:"
    echo "  - log it with context (logger.error / console.error with the error and what was being done)"
    echo "  - handle it (retry, fallback, return an error response) or re-throw"
    echo "  - if ignoring is truly intended, say why on the same or previous line: // ignore: <reason>   (Python: # ignore: <reason>)"
    echo "(Disable this check: MOGGER_CHECK_RESILIENCE=off.)"
  } >&2
  exit 2
fi
exit 0
