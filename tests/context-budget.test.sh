#!/usr/bin/env bash
# Fails when the text mogger puts in front of the model grows past a ceiling.
# Raise a ceiling ONLY with a reason in CHANGELOG.md: every extra character is
# paid for on every turn of every user's session.
# Run: bash tests/context-budget.test.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

# Ceilings (characters). Current values at the time of writing are noted.
MAX_ALWAYS=7600      # skill + agent descriptions, every turn (was ~12k at v1.7.0; trimmed to ~7.4k)
MAX_SESSION=1800     # session-start output on the fixture project (was 1934)
MAX_ONE_SKILL=16000  # biggest single skill body (mogger-loop ~15k)

out=$(bash "$ROOT/scripts/context-cost.sh" --json 2>&1)
num() { printf '%s' "$out" | sed -n "s/.*\"$1\":\([0-9]*\).*/\1/p"; }
ALWAYS=$(num always_on_chars); SESSION=$(num session_start_chars); BIGN=$(num biggest_skill_chars)

echo "== context-cost.sh"
[ -n "$ALWAYS" ] && ok "prints always_on_chars ($ALWAYS)" || bad "no always_on_chars in: $out"
[ -n "$SESSION" ] && ok "prints session_start_chars ($SESSION)" || bad "no session_start_chars"
printf '%s' "$out" | grep -q '"estimate":true' && ok "labelled as an estimate" || bad "not labelled estimate"
bash "$ROOT/scripts/context-cost.sh" | grep -q "ESTIMATE" && ok "text report says ESTIMATE" || bad "text report lacks ESTIMATE"

echo "== ceilings"
[ "${ALWAYS:-999999}" -le "$MAX_ALWAYS" ] && ok "always-on $ALWAYS <= $MAX_ALWAYS" || bad "always-on $ALWAYS > $MAX_ALWAYS"
[ "${SESSION:-999999}" -le "$MAX_SESSION" ] && ok "session-start $SESSION <= $MAX_SESSION" || bad "session-start $SESSION > $MAX_SESSION"
[ "${BIGN:-999999}" -le "$MAX_ONE_SKILL" ] && ok "biggest skill body $BIGN <= $MAX_ONE_SKILL" || bad "biggest skill body $BIGN > $MAX_ONE_SKILL"
[ "${ALWAYS:-0}" -gt 1000 ] && ok "sanity: always-on is not zero (script really counts)" || bad "always-on suspiciously small: $ALWAYS"

echo; echo "context-budget: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
