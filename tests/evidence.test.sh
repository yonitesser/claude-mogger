#!/usr/bin/env bash
# Hook-written test evidence + the STATUS.md deadlock. Run: bash tests/evidence.test.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
H="$ROOT/hooks/scripts"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
SB=$(mktemp -d); trap 'rm -rf "$SB"' EXIT; cd "$SB"
export CLAUDE_PROJECT_DIR="$SB"; unset MOGGER_EVIDENCE MOGGER_TEST_CMD_REGEX
mkdir -p .claude/state; echo x > app.js
post()  { printf '{"hook_event_name":"PostToolUse","tool_input":{"command":"%s"},"tool_response":{"stdout":"%s","stderr":""}}' "$1" "${2:-ok}" | bash "$H/record-test-run.sh"; }
fail()  { printf '{"hook_event_name":"PostToolUseFailure","tool_input":{"command":"%s"},"error":"Exit code %s\\nFAILED"}' "$1" "${2:-1}" | bash "$H/record-test-run.sh"; }
ev()    { python3 -c 'import json;print(json.load(open(".claude/state/test-evidence.json"))["status"])' 2>/dev/null; }
gate()  { printf '{"tool_name":"Task","tool_input":{"subagent_type":"reviewer"}}' | bash "$H/require-tests-pass.sh" >/dev/null 2>&1; echo $?; }

echo "== recorder"
post "npm test"; [ "$(ev)" = pass ] && ok "npm test exit 0 -> pass" || bad "pass not recorded"
fail "pytest -q" 1; [ "$(ev)" = fail ] && ok "pytest exit 1 -> fail" || bad "fail not recorded"
post "npm test | tail" "2 failed, 3 passed"; [ "$(ev)" = fail ] && ok "piped run with '2 failed' -> fail" || bad "piped failure missed"
# the status-bar mod's "pass" moment: logged on a pass only
rm -f .claude/state/mogger-events.log; post "npm test"
grep -q "$(printf 'ok\ttests passed')" .claude/state/mogger-events.log && ok "a passing run logs 'tests passed'" || bad "pass event missing"
rm -f .claude/state/mogger-events.log; fail "pytest -q" 1
[ -f .claude/state/mogger-events.log ] && bad "failing run logged a pass" || ok "a failing run logs no pass event"
post "npm test"; rm .claude/state/test-evidence.json
post "npm run lint"; [ -f .claude/state/test-evidence.json ] && bad "lint wrote evidence" || ok "lint alone is not recorded"
post "echo npm test"; [ -f .claude/state/test-evidence.json ] && bad "echo wrote evidence" || ok "echo is not a run"
fail "pytest" 127; [ -f .claude/state/test-evidence.json ] && bad "127 wrote evidence" || ok "command not found is not a test failure"
MOGGER_TEST_CMD_REGEX='run_all' post "./run_all.sh"; [ "$(ev)" = pass ] && ok "MOGGER_TEST_CMD_REGEX adds a runner" || bad "custom regex ignored"
MOGGER_EVIDENCE=off post "npm test"; echo '{"status":"fail"}' > .claude/state/test-evidence.json
MOGGER_EVIDENCE=off post "npm test"; [ "$(ev)" = fail ] && ok "MOGGER_EVIDENCE=off writes nothing" || bad "off switch ignored"

echo "== reviewer gate needs real evidence"
echo '{"status":"pass","exit_code":0,"scope":"full"}' > .claude/state/last_test_result.json
rm -f .claude/state/test-evidence.json
[ "$(gate)" = 2 ] && ok "tester says pass, no hook evidence -> blocked" || bad "forged marker accepted"
fail "npm test" 1
[ "$(gate)" = 2 ] && ok "last real run failed -> blocked despite pass marker" || bad "failed run accepted"
sleep 1; post "npm test"; touch -d '2000-01-01' app.js
[ "$(gate)" = 0 ] && ok "real pass + marker pass -> allowed" || bad "valid pass blocked"
MOGGER_EVIDENCE=off bash -c 'rm .claude/state/test-evidence.json; printf "{\"tool_name\":\"Task\",\"tool_input\":{\"subagent_type\":\"reviewer\"}}" | bash "'$H'/require-tests-pass.sh" >/dev/null 2>&1'; [ $? = 0 ] && ok "MOGGER_EVIDENCE=off falls back to the marker" || bad "off switch broken"
post "npm test"; touch -d '2000-01-01' app.js

echo "== STATUS.md rewrite does not make the pass stale (deadlock)"
sleep 1; echo "# STATUS" > STATUS.md
[ "$(gate)" = 0 ] && ok "STATUS.md newer than the test run -> still allowed" || bad "STATUS.md deadlock"
sleep 1; echo y >> app.js
[ "$(gate)" = 2 ] && ok "real source edit after the run -> stale" || bad "stale edit missed"

echo "== model cannot write the evidence file"
printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.claude/state/test-evidence.json"}}' "$SB" | bash "$H/protect-pipeline-files.sh" >/dev/null 2>&1
[ $? = 2 ] && ok "Write to test-evidence.json blocked" || bad "evidence write allowed"
echo "evidence: $PASS passed, $FAIL failed"; [ "$FAIL" = 0 ]
