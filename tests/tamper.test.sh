#!/usr/bin/env bash
# Tests for check-test-tamper.sh. Run: bash tests/tamper.test.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
H="$ROOT/hooks/scripts/check-test-tamper.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
SB=$(mktemp -d); trap 'rm -rf "$SB"' EXIT
cd "$SB"; git init -q . ; git config user.email t@t; git config user.name t
mkdir tests
cat > tests/test_a.py <<'PY'
def test_one():
    assert f(1) == 2
    assert f(2) == 3

def test_two():
    assert f(0) == 1
PY
git add -A; git commit -q -m base
run() { printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/%s"}}' "$SB" "$1" | bash "$H" 2>"$SB/err" >/dev/null; echo $?; }
warns() { grep -q "Test weakened" "$SB/err"; }

echo "== unchanged file is silent"
rc=$(run tests/test_a.py); [ "$rc" = 0 ] && ! warns && ok "no change -> no warning" || bad "unchanged warned"

echo "== removed assertion warns, never blocks"
grep -v 'f(2) == 3' tests/test_a.py > tests/t.tmp; mv tests/t.tmp tests/test_a.py
rc=$(run tests/test_a.py); [ "$rc" = 0 ] && warns && ok "assertion removed -> warns, exit 0" || bad "removed assertion not flagged"
git checkout -q tests/test_a.py

echo "== removed test case warns"
python3 - <<'PY'
s=open('tests/test_a.py').read(); i=s.index('def test_two'); open('tests/test_a.py','w').write(s[:i])
PY
rc=$(run tests/test_a.py); [ "$rc" = 0 ] && warns && grep -q "test cases" "$SB/err" && ok "case removed -> warns" || bad "removed case not flagged"
git checkout -q tests/test_a.py

echo "== added skip warns"
python3 -c "p='tests/test_a.py';s=open(p).read();open(p,'w').write(s.replace('def test_two','@pytest.mark.skip\\ndef test_two',1))"
rc=$(run tests/test_a.py); [ "$rc" = 0 ] && warns && ok "skip added -> warns" || bad "skip not flagged"
git checkout -q tests/test_a.py

echo "== adding tests is silent; non-test and new files are silent"
printf 'def test_three():\n    assert f(5) == 6\n' >> tests/test_a.py
rc=$(run tests/test_a.py); [ "$rc" = 0 ] && ! warns && ok "more assertions -> silent" || bad "growth warned"
git checkout -q tests/test_a.py
printf 'x=1\n' > app.py; git add app.py; git commit -q -m app; : > app.py
rc=$(run app.py); [ "$rc" = 0 ] && ! warns && ok "non-test file -> silent" || bad "non-test warned"
printf 'def test_new():\n    pass\n' > tests/test_new.py
rc=$(run tests/test_new.py); [ "$rc" = 0 ] && ! warns && ok "untracked new test -> silent" || bad "new file warned"

echo "== escape hatch"
grep -v 'f(2) == 3' tests/test_a.py > tests/t.tmp; mv tests/t.tmp tests/test_a.py
rc=$(printf '{"tool_input":{"file_path":"%s/tests/test_a.py"}}' "$SB" | MOGGER_CHECK_TAMPER=off bash "$H" 2>"$SB/err"; echo $?)
[ "$rc" = 0 ] && ! warns && ok "MOGGER_CHECK_TAMPER=off is silent" || bad "escape hatch ignored"

echo; echo "tamper: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
