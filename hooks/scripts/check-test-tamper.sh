#!/usr/bin/env bash
# PostToolUse — matcher: Edit|Write
# Warns when an edit to an EXISTING test file removes assertions, removes or
# renames away test cases, or adds skips, compared with the version first seen
# this session (.claude/state/test-baseline, written by track-edits.sh) or, if
# there is none, the committed (HEAD) version. Agents often go green by
# weakening the test, not by fixing the code. Costs no model tokens: it only
# speaks when something is lost. WARN only (additionalContext, exit 0) because
# honest refactors also remove assertions; the model must say why and keep the
# behaviour covered. Update a changed test IN PLACE under its old name.
# Counts are heuristic (regex). Anything it cannot read => silent. New files
# and non-tests => silent.
# Escape hatch: MOGGER_CHECK_TAMPER=off.

[ "${MOGGER_CHECK_TAMPER:-on}" = "off" ] && exit 0
MOGGER_TQ_SOURCE_ONLY=1 source "$(dirname "$0")/check-test-quality.sh" 2>/dev/null
source "$(dirname "$0")/lib.sh"

INPUT=$(cat)
FP=$(json_get "$INPUT" '.tool_input.file_path')
[ -n "$FP" ] && [ -f "$FP" ] || exit 0
REL="$FP"
case "$FP" in "$PWD"/*) REL="${FP#"$PWD"/}" ;; esac
tq_is_test_path "$REL" || exit 0
KEY=$(printf '%s' "$REL" | cksum | cut -d' ' -f1)
BASE=".claude/state/test-baseline/$KEY"
if [ -f "$BASE" ]; then
  OLD=$(cat "$BASE")
elif command -v git >/dev/null 2>&1 && git cat-file -e "HEAD:$REL" 2>/dev/null; then
  OLD=$(git show "HEAD:$REL" 2>/dev/null) || exit 0
else
  exit 0   # nothing to compare against
fi
NEW=$(cat "$FP")

ASSERT_RE='(^|[^[:alnum:]_])(assert[A-Za-z_]*[ (]|expect\(|self\.assert|t\.(Error|Fatal|Fail)|require\.|\.should\b|pytest\.raises)'
CASE_RE='^[[:space:]]*(def test_|async def test_|(it|test)\(|func Test|(it|test)\.each)'
SKIP_RE='(\.skip\(|xit\(|xtest\(|pytest\.mark\.skip|t\.Skip\(|@unittest\.skip)'

count() { grep -Ec "$2" <<<"$1" || true; }
OA=$(count "$OLD" "$ASSERT_RE"); NA=$(count "$NEW" "$ASSERT_RE")
OC=$(count "$OLD" "$CASE_RE");   NC=$(count "$NEW" "$CASE_RE")
OS=$(count "$OLD" "$SKIP_RE");   NS=$(count "$NEW" "$SKIP_RE")

NAME_RE='(def test_[A-Za-z0-9_]+|(it|test)\(["'"'"'`][^"'"'"'`]+|func Test[A-Za-z0-9_]+)'
names() { grep -Eo "$NAME_RE" <<<"$1" | sort -u; }
GONE=$(comm -23 <(names "$OLD") <(names "$NEW") | head -3 | tr '\n' ',' | sed 's/,$//')

MSG=""
[ "$NA" -lt "$OA" ] && MSG="assertions ${OA} -> ${NA}"
[ "$NC" -lt "$OC" ] && MSG="${MSG:+$MSG; }test cases ${OC} -> ${NC}"
[ -n "$GONE" ] && MSG="${MSG:+$MSG; }tests no longer present (deleted or renamed): ${GONE}"
[ "$NS" -gt "$OS" ] && MSG="${MSG:+$MSG; }skipped tests ${OS} -> ${NS}"
[ -z "$MSG" ] && exit 0

TEXT="Test weakened? ${REL}: ${MSG} vs the original. If the code is wrong, fix the code, not the test. If a test must change, update it in place under its old name. If a removal is deliberate, say why in one line and keep the behaviour covered."
echo "mogger: $TEXT" >&2
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' "$(tq_json_escape "$TEXT")"
exit 0
