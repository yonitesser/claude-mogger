#!/usr/bin/env bash
# Tests for track-edits.sh, stop-tests-added.sh and the git-free baseline in
# check-test-tamper.sh. Run: bash tests/gates.test.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
H="$ROOT/hooks/scripts"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
SB=$(mktemp -d); trap 'rm -rf "$SB"' EXIT
cd "$SB"   # NOT a git repo on purpose: the eval workspaces are not repos
mkdir -p tests app
printf 'def test_one():\n    assert f(1) == 2\n    assert f(2) == 3\n\ndef test_two():\n    assert f(0) == 1\n' > tests/test_a.py
printf 'def f(x):\n    return x + 1\n' > app/main.py
pre()  { printf '{"tool_input":{"file_path":"%s/%s"}}' "$SB" "$1" | bash "$H/track-edits.sh" >/dev/null 2>&1; }
post() { printf '{"tool_input":{"file_path":"%s/%s"}}' "$SB" "$1" | bash "$H/check-test-tamper.sh" 2>"$SB/err" >/dev/null; echo $?; }
stop() { printf '{"stop_hook_active":%s}' "${1:-false}" | bash "$H/stop-tests-added.sh" 2>"$SB/err" >/dev/null; echo $?; }

echo "== track-edits"
pre tests/test_a.py; pre app/main.py
[ "$(ls .claude/state/test-baseline | wc -l | tr -d ' ')" = 1 ] && ok "baseline copy of the test file taken" || bad "no baseline"
grep -q '^T tests/test_a.py' .claude/state/edits.log && grep -q '^C app/main.py' .claude/state/edits.log && ok "test and code edits logged" || bad "edits.log wrong: $(cat .claude/state/edits.log)"

echo "== tamper works without git (baseline)"
grep -v 'f(2) == 3' tests/test_a.py > tests/t.tmp; mv tests/t.tmp tests/test_a.py
rc=$(post tests/test_a.py); [ "$rc" = 0 ] && grep -q "Test weakened" "$SB/err" && ok "assertion removed -> warns" || bad "baseline not used"
printf 'def test_one():\n    assert f(1) == 2\n    assert f(2) == 3\n\ndef test_renamed():\n    assert f(0) == 1\n' > tests/test_a.py
pre tests/test_a.py
rc=$(post tests/test_a.py); grep -q "test_two" "$SB/err" && ok "renamed-away test named in warning" || bad "rename not caught: $(cat "$SB/err")"
printf 'def test_one():\n    assert f(1) == 2\n    assert f(2) == 3\n\ndef test_two():\n    assert f(0) == 1\ndef test_three():\n    assert f(3) == 4\n' > tests/test_a.py
rc=$(post tests/test_a.py); [ "$rc" = 0 ] && ! grep -q "Test weakened" "$SB/err" && ok "added test -> silent" || bad "growth warned"

echo "== stop-tests-added"
: > .claude/state/edits.log
pre app/main.py; rc=$(stop); [ "$rc" = 0 ] && ok "one small code edit -> passes (typo fixes are not features)" || bad "small edit blocked"
pre app/main.py; pre app/main.py; pre app/main.py
rc=$(stop); [ "$rc" = 2 ] && grep -q "NO TESTS" "$SB/err" && ok "code changed, no test -> blocks" || bad "gate silent (rc=$rc)"
rc=$(stop); [ "$rc" = 0 ] && ok "log cleared: next stop passes" || bad "blocked twice"
pre app/main.py; pre app/main.py; pre app/main.py; rc=$(stop true); [ "$rc" = 0 ] && ok "stop_hook_active -> never loops" || bad "looped"
pre app/main.py; pre app/main.py; pre app/main.py; pre tests/test_a.py; rc=$(stop); [ "$rc" = 0 ] && ok "code plus test -> passes" || bad "blocked with tests present"
printf 'x\n' > README.md; pre README.md; rc=$(stop); [ "$rc" = 0 ] && ok "docs only -> passes" || bad "docs blocked"
pre app/main.py; pre app/main.py; pre app/main.py; rc=$(MOGGER_TESTS_ADDED=off stop); [ "$rc" = 0 ] && ok "escape hatch" || bad "escape hatch ignored"

echo; echo "gates: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
