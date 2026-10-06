#!/usr/bin/env bash
# PostToolUse — matcher: Edit|Write
# Warns when an edit to an EXISTING test file removes assertions or test cases
# compared with the committed (HEAD) version. Agents often go green by
# weakening the test, not by fixing the code. Costs no model tokens: it only
# speaks when the count drops. WARN only (additionalContext, exit 0) because
# honest refactors also remove assertions; the model must say why, in its
# next message, and keep the behaviour covered.
# Counts are heuristic (regex on assert/expect/test-case lines). Anything it
# cannot read => silent. New files, untracked files, non-tests => silent.
# Escape hatch: MOGGER_CHECK_TAMPER=off. Fails open without git.

[ "${MOGGER_CHECK_TAMPER:-on}" = "off" ] && exit 0
MOGGER_TQ_SOURCE_ONLY=1 source "$(dirname "$0")/check-test-quality.sh" 2>/dev/null
source "$(dirname "$0")/lib.sh"
command -v git >/dev/null 2>&1 || exit 0

INPUT=$(cat)
FP=$(json_get "$INPUT" '.tool_input.file_path')
[ -n "$FP" ] && [ -f "$FP" ] || exit 0
REL="$FP"
case "$FP" in "$PWD"/*) REL="${FP#"$PWD"/}" ;; esac
tq_is_test_path "$REL" || exit 0
git cat-file -e "HEAD:$REL" 2>/dev/null || exit 0   # not committed yet: nothing to compare

ASSERT_RE='(^|[^[:alnum:]_])(assert[A-Za-z_]*[ (]|expect\(|self\.assert|t\.(Error|Fatal|Fail)|require\.|\.should\b|pytest\.raises)'
CASE_RE='^[[:space:]]*(def test_|async def test_|(it|test)\(|func Test|(it|test)\.each)'
SKIP_RE='(\.skip\(|xit\(|xtest\(|pytest\.mark\.skip|t\.Skip\(|@unittest\.skip)'

count() { grep -Ec "$2" <<<"$1" || true; }
OLD=$(git show "HEAD:$REL" 2>/dev/null) || exit 0
NEW=$(cat "$FP")
OA=$(count "$OLD" "$ASSERT_RE"); NA=$(count "$NEW" "$ASSERT_RE")
OC=$(count "$OLD" "$CASE_RE");   NC=$(count "$NEW" "$CASE_RE")
OS=$(count "$OLD" "$SKIP_RE");   NS=$(count "$NEW" "$SKIP_RE")

MSG=""
[ "$NA" -lt "$OA" ] && MSG="assertions ${OA} -> ${NA}"
[ "$NC" -lt "$OC" ] && MSG="${MSG:+$MSG; }test cases ${OC} -> ${NC}"
[ "$NS" -gt "$OS" ] && MSG="${MSG:+$MSG; }skipped tests ${OS} -> ${NS}"
[ -z "$MSG" ] && exit 0

TEXT="Test weakened? ${REL}: ${MSG} vs the committed version. If the code is wrong, fix the code, not the test. If this removal is deliberate, say why in one line and keep the behaviour covered."
echo "mogger: $TEXT" >&2
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' "$(tq_json_escape "$TEXT")"
exit 0
