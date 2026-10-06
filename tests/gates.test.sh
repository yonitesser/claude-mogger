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

echo "== stop runs the project tests"
printf '{"name":"x","scripts":{"test":"exit 1"}}' > package.json
pre app/main.py; rc=$(stop); [ "$rc" = 2 ] && grep -q "TESTS FAIL" "$SB/err" && ok "red suite -> blocks the stop" || bad "red suite passed (rc=$rc)"
pre app/main.py; rc=$(stop true); [ "$rc" = 0 ] && ok "stop_hook_active -> no loop on red" || bad "looped on red"
printf '{"name":"x","scripts":{"test":"exit 0"}}' > package.json
pre app/main.py; rc=$(stop); [ "$rc" = 0 ] && ok "green suite -> passes" || bad "green suite blocked"
printf '{"name":"x","scripts":{"test":"exit 1"}}' > package.json
rc=$(stop); [ "$rc" = 0 ] && ok "no edits this turn -> suite not run" || bad "ran with no edits"
pre app/main.py; rc=$(MOGGER_STOP_TESTS=off stop); [ "$rc" = 0 ] && ok "escape hatch for the test run" || bad "hatch ignored"
printf '{"name":"x","scripts":{"test":"echo \\"Error: no test specified\\" && exit 1"}}' > package.json
pre app/main.py; rc=$(stop); [ "$rc" = 0 ] && ok "npm default stub ignored" || bad "stub counted as a suite"
rm -f package.json

echo "== stop-claim-check"
tr() { printf '%s\n' "$@" > "$SB/tr.jsonl"; }
U='{"type":"user","message":{"role":"user","content":"add a coupon"}}'
E='{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/a/cart.py"}}]}}'
R='{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"python3 -m unittest"}}]}}'
D='{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Done, all tests pass."}]}}'
Q='{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Which rounding do you want?"}]}}'
cc() { printf '{"transcript_path":"%s/tr.jsonl","stop_hook_active":%s}' "$SB" "${1:-false}" | bash "$H/stop-claim-check.sh" 2>"$SB/err" >/dev/null; echo $?; }
tr "$U" "$E" "$D"; rc=$(cc); [ "$rc" = 2 ] && grep -q "NOT PROVEN" "$SB/err" && ok "claim, no run after edit -> blocked as not proven" || bad "noproof not blocked"
tr "$U" "$E" "$R" "$D"; rc=$(cc); [ "$rc" = 0 ] && ok "claim after a run -> silent by default (0 tokens)" || bad "default mode blocked a proven claim"
tr "$U" "$E" "$R" "$D"; rc=$(MOGGER_CLAIM_CHECK=always cc); [ "$rc" = 2 ] && ! grep -q "NOT PROVEN" "$SB/err" && grep -q "CHECK BEFORE" "$SB/err" && ok "always mode -> requirement check after a run" || bad "always mode did not check"
tr "$U" "$E" "$R" "$D"; rc=$(cc true); [ "$rc" = 0 ] && ok "stop_hook_active -> no loop" || bad "looped"
tr "$U" "$E" "$Q"; rc=$(cc); [ "$rc" = 0 ] && ok "no claim -> silent" || bad "blocked a question"
tr "$U" "$D"; rc=$(cc); [ "$rc" = 0 ] && ok "no code edit -> silent" || bad "blocked without edits"
tr "$U" '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/a/README.md"}}]}}' "$D"; rc=$(cc); [ "$rc" = 0 ] && ok "docs-only edit -> silent" || bad "blocked docs edit"
B='{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"python3 - <<E\nopen(\"shop/cart.py\",\"w\").write(s)\nE"}}]}}'
tr "$U" "$B" "$D"; rc=$(cc); [ "$rc" = 2 ] && ok "edit done through a Bash script counts as a code edit" || bad "bash edit missed"
tr "$U" "$B" "$R" "$D"; rc=$(MOGGER_CLAIM_CHECK=always cc); [ "$rc" = 2 ] && grep -q "CHECK BEFORE" "$SB/err" && ! grep -q "NOT PROVEN" "$SB/err" && ok "bash edit then a run -> requirement check" || bad "bash edit then run wrong"
# no transcript (eval runner): git/file fingerprint decides
ERRD=$(mktemp -d)   # outside the work tree, so the fingerprint ignores it
NT() { printf '{"stop_hook_active":false,"last_assistant_message":"%s"}' "$1" | bash "$H/stop-claim-check.sh" 2>"$ERRD/err" >/dev/null; echo $?; }
source "$H/claim-lib.sh"; claim_baseline
rc=$(NT "Done, it works."); [ "$rc" = 0 ] && ok "no transcript, nothing changed -> silent" || bad "blocked with no change"
printf 'def f(x):\n    return x + 2\n' > app/main.py
rc=$(MOGGER_CLAIM_CHECK=always NT "Done, it works."); [ "$rc" = 2 ] && grep -q "CHECK BEFORE" "$ERRD/err" && ok "no transcript, code changed + claim -> check" || bad "fingerprint path missed"
rc=$(MOGGER_CLAIM_CHECK=always NT "Done, it works."); [ "$rc" = 0 ] && ok "same change not re-checked next turn" || bad "re-fired on same change"
printf 'def f(x):\n    return x + 3\n' > app/main.py
rc=$(NT "Which one do you want?"); [ "$rc" = 0 ] && ok "no transcript, changed but no claim -> silent" || bad "blocked a question"
tr "$U" "$E" "$D"; rc=$(MOGGER_CLAIM_CHECK=off cc); [ "$rc" = 0 ] && ok "escape hatch" || bad "hatch ignored"
tr "$E" "$D" "$U" "$Q"; rc=$(cc); [ "$rc" = 0 ] && ok "earlier turn's edits not counted" || bad "old turn counted"

echo; echo "gates: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
