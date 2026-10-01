#!/usr/bin/env bash
# Tests for check-test-quality.sh, tests-quality.sh, fix-loop-guard.sh.
# Run: bash tests/testing.test.sh   (self-contained temp sandbox, no network)
# Exits non-zero on any failure.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
H="$ROOT/hooks/scripts"
PASS=0; FAIL=0

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
cd "$SANDBOX"
git init -q -b main . 2>/dev/null || { git init -q .; git checkout -q -b main; }
mkdir -p t

ok()  { PASS=$((PASS+1)); printf '  ok   %-22s %s\n' "$1" "$2"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %-22s %s\n' "$1" "$2"; }

ERR=""; OUTP=""; RC=0
# tq <relative test file> -> sets RC / ERR / OUTP from the quality hook
tq() {
  local f="$1"
  ERR=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/%s"}}' "$SANDBOX" "$f" | bash "$H/check-test-quality.sh" 2>&1 >"$SANDBOX/.out"); RC=$?
  OUTP=$(cat "$SANDBOX/.out")
}
blocks() {  # blocks <file> <needle-in-stderr> <desc>
  tq "$1"
  if [ "$RC" -eq 2 ] && case "$ERR" in *"$2"*) true ;; *) false ;; esac; then ok check-test-quality "$3"; else bad check-test-quality "$3 (rc=$RC err=$ERR)"; fi
}
allows() {  # allows <file> <desc>   exit 0 and no BLOCKED
  tq "$1"
  if [ "$RC" -eq 0 ] && case "$ERR" in *BLOCKED*) false ;; *) true ;; esac; then ok check-test-quality "$2"; else bad check-test-quality "$2 (rc=$RC err=$ERR)"; fi
}
warns() {   # warns <file> <needle> <desc>  exit 0 + stderr WARN
  tq "$1"
  if [ "$RC" -eq 0 ] && case "$ERR" in *"$2"*) true ;; *) false ;; esac; then ok check-test-quality "$3"; else bad check-test-quality "$3 (rc=$RC err=$ERR)"; fi
}

fx_js_bad() {
cat > t/empty.test.js <<'J'
describe('cart', () => {
  it('adds an item', () => {});
});
J
cat > t/noassert.test.js <<'J'
import { render } from '@testing-library/react';
describe('page', () => {
  it('renders the page', () => {
    render(<Page />);
  });
});
J
cat > t/taut.test.ts <<'J'
test('always passes', () => {
  expect(true).toBe(true);
});
J
cat > t/taut2.spec.ts <<'J'
it('same token', () => {
  const x = compute();
  expect(x).toBe(x);
});
J
cat > t/taut3.test.js <<'J'
it('literal', () => { expect(1).toEqual(1); });
it('truthy', () => { expect(true).toBeTruthy(); });
J
cat > t/only.test.js <<'J'
describe('a', () => {
  it.only('focused', () => { expect(f()).toBe(2); });
});
J
cat > t/fit.test.js <<'J'
fit('focused', () => { expect(f()).toBe(2); });
J
cat > t/fdescribe.test.js <<'J'
fdescribe('focused', () => { it('x', () => { expect(f()).toBe(2); }); });
J
}
fx_js_good() {
cat > t/helper.test.js <<'J'
function assertShape(r) {
  expect(r).toHaveProperty('id');
}
function runScenario(x) {
  const r = go(x);
  expect(r.ok).toBe(true);
  return r;
}
it('uses assert helper', () => {
  assertShape(go(1));
});
it('uses scenario helper without a visible expect', () => {
  runScenario(2);
});
J
cat > t/each.test.js <<'J'
test.each([[1, 2], [3, 4]])('adds %i', (a, b) => {
  expect(add(a, 1)).toBe(b);
});
it.each([1, 2])('runs %i', (n) => {
  doThing(n);
});
J
cat > t/names.test.js <<'J'
describe('should assert things', () => {
  it('should expect a value: (parens) and "quotes"', async () => {
    const r = await go('expect(true).toBe(true)');
    expect(r).toBe('ok');
  });
  it('supertest style', async () => {
    await request(app).get('/x').expect(200);
  });
  it('throws on bad input', () => {
    expect(() => parse('')).toThrow();
  });
  it('resolves', async () => {
    await expect(load()).resolves.toEqual({ a: 1 });
  });
  it('different values', () => {
    expect(next()).toBe(next());
    expect(a).not.toBe(a);
    expect('a').toBe('b');
  });
});
J
cat > t/e2e.spec.ts <<'J'
import { test } from '@playwright/test';
test('opens home', async ({ page }) => {
  await page.goto('/');
  await page.getByText('Welcome').click();
});
J
cat > t/rtl.test.tsx <<'J'
it('shows title', () => {
  render(<App />);
  screen.getByText('Hello');
});
J
cat > t/comment.test.js <<'J'
// it('commented out', () => {});
/*
it('block commented', () => {});
*/
it('real', () => { expect(1 + 1).toBe(2); });
J
cat > t/pending.test.js <<'J'
it('todo later');
it.todo('write this');
J
cat > t/multi.test.js <<'J'
it('multi-line call', async () => {
  const result = await service.create({
    name: 'x',
    tags: ['a', 'b'],
  });
  expect(result).toEqual({
    id: 1,
  });
});
J
}
fx_py() {
cat > t/test_empty.py <<'P'
def test_nothing():
    pass

def test_doc_only():
    """Explains but asserts nothing."""
P
cat > t/test_noassert.py <<'P'
def test_runs():
    result = compute(3)
    print(result)
P
cat > t/test_taut.py <<'P'
def test_a():
    assert True

def test_b():
    assert 1 == 1

def test_c():
    x = f()
    assert x == x
P
cat > t/test_good.py <<'P'
import pytest
from tests.helpers import check_all

def _validate(r):
    assert r.ok

def test_value():
    assert compute(2) == 4

def test_raises():
    with pytest.raises(ValueError):
        compute(-1)

def test_helper_local():
    _validate(compute(1))

def test_helper_imported():
    check_all(compute(1))

def test_calls_differ():
    assert f() == f()

def test_not_equal_strings():
    assert "a" == "b" or True is not False

class TestThing(object):
    def test_method(self):
        self.assertEqual(compute(1), 1)

    def test_other(self):
        self.assertEqual(a, b)

async def test_async():
    assert await load() == 3
P
cat > t/test_skip.py <<'P'
import pytest

@pytest.mark.skip
def test_skipped():
    assert compute() == 1

@pytest.mark.skip(reason="waiting on API v2")
def test_skipped_reason():
    assert compute() == 1

@pytest.mark.skip  # flaky on CI, see #123
def test_skipped_comment():
    assert compute() == 1
P
}
fx_go() {
cat > t/bad_test.go <<'G'
package x

import "testing"

func TestEmpty(t *testing.T) {
}

func TestNoAssert(t *testing.T) {
	r := Compute(3)
	_ = r
}
G
cat > t/good_test.go <<'G'
package x

import "testing"

func TestTable(t *testing.T) {
	tests := []struct {
		name string
		in   int
		want int
	}{
		{"one", 1, 1},
		{"two", 2, 4},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := Sq(tt.in); got != tt.want {
				t.Errorf("Sq(%d) = %d, want %d", tt.in, got, tt.want)
			}
		})
	}
}

func TestDirect(t *testing.T) {
	if Sq(3) != 9 {
		t.Fatal("bad")
	}
}

func TestViaHelper(t *testing.T) {
	checkSquare(t, 4, 16)
}

func TestWithAssert(t *testing.T) {
	assert.Equal(t, 9, Sq(3))
}

func TestMain(m *testing.M) {
	os.Exit(m.Run())
}

func helperNotATest() {}
G
cat > t/skip_test.go <<'G'
package x

import "testing"

func TestSkipped(t *testing.T) {
	t.Skip()
}

func TestSkippedReason(t *testing.T) {
	t.Skip("needs docker")
}
G
}
fx_js_bad; fx_js_good; fx_py; fx_go

echo "== check-test-quality.sh: blocks fake tests (JS/TS)"
blocks t/empty.test.js "t/empty.test.js:2" "empty test body blocked with file:line"
blocks t/empty.test.js "empty test body" "empty test body message"
blocks t/noassert.test.js "t/noassert.test.js:3" "test with no assertion blocked at test start line"
blocks t/taut.test.ts "t/taut.test.ts:2" "expect(true).toBe(true) blocked"
blocks t/taut2.spec.ts "t/taut2.spec.ts:3" "expect(x).toBe(x) blocked"
blocks t/taut3.test.js "t/taut3.test.js:1" "expect(1).toEqual(1) blocked"
blocks t/taut3.test.js "t/taut3.test.js:2" "expect(true).toBeTruthy() blocked"
blocks t/only.test.js "t/only.test.js:2" ".only committed blocked"
blocks t/fit.test.js "t/fit.test.js:1" "fit( committed blocked"
blocks t/fdescribe.test.js "t/fdescribe.test.js:1" "fdescribe committed blocked"

echo "== check-test-quality.sh: false-positive guards (JS/TS)"
allows t/helper.test.js "expect inside a same-file helper called from the test"
allows t/each.test.js "test.each / it.each never flagged"
allows t/names.test.js "assertion words inside test names/strings; supertest .expect; toThrow; resolves; different values"
allows t/e2e.spec.ts "playwright page.* steps count as assertions"
allows t/rtl.test.tsx "testing-library getByText counts as assertion"
allows t/comment.test.js "commented-out tests ignored"
allows t/pending.test.js "it('x') without callback / it.todo not flagged"
allows t/multi.test.js "multi-line call with expect at the end"

echo "== check-test-quality.sh: Python"
blocks t/test_empty.py "t/test_empty.py:1" "pass-only test blocked"
blocks t/test_empty.py "t/test_empty.py:4" "docstring-only test blocked"
blocks t/test_noassert.py "t/test_noassert.py:1" "python test without assert blocked"
blocks t/test_taut.py "t/test_taut.py:2" "assert True blocked"
blocks t/test_taut.py "t/test_taut.py:5" "assert 1 == 1 blocked"
blocks t/test_taut.py "t/test_taut.py:9" "assert x == x blocked"
allows t/test_good.py "pytest.raises, helpers, assert f()==f(), self.assertEqual, async, class methods"
warns t/test_skip.py "test_skip.py:3" "bare @pytest.mark.skip warns (exit 0)"
tq t/test_skip.py
case "$ERR" in *"test_skip.py:7"*|*"test_skip.py:11"*) bad check-test-quality "skip with reason/comment must not warn ($ERR)" ;; *) ok check-test-quality "skip with reason= or comment does not warn" ;; esac
case "$OUTP" in *additionalContext*) ok check-test-quality "warning also delivered as additionalContext JSON" ;; *) bad check-test-quality "additionalContext missing ($OUTP)" ;; esac

echo "== check-test-quality.sh: Go"
blocks t/bad_test.go "t/bad_test.go:5" "empty Go test blocked"
blocks t/bad_test.go "t/bad_test.go:8" "Go test with no t.Error/assert blocked"
allows t/good_test.go "Go table test, t.Fatal, helper(t,...), assert.Equal, TestMain"
warns t/skip_test.go "skip_test.go:6" "t.Skip() with no reason warns"
tq t/skip_test.go
case "$ERR" in *"skip_test.go:10"*) bad check-test-quality "t.Skip(reason) must not warn" ;; *) ok check-test-quality "t.Skip(\"reason\") does not warn" ;; esac

echo "== check-test-quality.sh: skips / mocks / scoping / fail-open"
cat > t/skipjs.test.js <<'J'
it.skip('no reason', () => { expect(f()).toBe(1); });
// flaky on CI: see #42
it.skip('has reason', () => { expect(f()).toBe(1); });
xit('bare xit', () => { expect(f()).toBe(2); });
J
tq t/skipjs.test.js
if [ "$RC" -eq 0 ]; then ok check-test-quality ".skip/xit only warn (exit 0)"; else bad check-test-quality ".skip should not block"; fi
case "$ERR" in *"skipjs.test.js:1"*"skipjs.test.js:4"*) ok check-test-quality "unreasoned it.skip and xit warned with lines" ;; *) bad check-test-quality "skip lines ($ERR)" ;; esac
case "$ERR" in *"skipjs.test.js:3"*) bad check-test-quality "skip with comment reason must not warn" ;; *) ok check-test-quality "it.skip with comment above not warned" ;; esac
cat > t/mock.test.js <<'J'
jest.mock('./mailer');
it('sends mail', () => {
  signup('a@b.c');
  expect(mailer.send).toHaveBeenCalled();
});
it('sends and checks result', () => {
  const r = signup('a@b.c');
  expect(mailer.send).toHaveBeenCalled();
  expect(r.ok).toBe(true);
});
J
tq t/mock.test.js
if [ "$RC" -eq 0 ]; then ok check-test-quality "mock-only test warns, never blocks"; else bad check-test-quality "mock-only must not block"; fi
case "$ERR" in *"mock.test.js:2"*HEURISTIC*) ok check-test-quality "mock-only warning labelled HEURISTIC with line" ;; *) bad check-test-quality "mock warning ($ERR)" ;; esac
case "$ERR" in *"mock.test.js:6"*) bad check-test-quality "test with a real assertion beside the mock check must not warn" ;; *) ok check-test-quality "mock check plus real assertion not warned" ;; esac

mkdir -p src tests/unit
cat > src/util.js <<'J'
it('not a test file location', () => {});
J
allows src/util.js "non-test file ignored even if it looks like a test"
cat > tests/unit/helper.py <<'P'
def make_thing():
    return 1
P
allows tests/unit/helper.py "helper under tests/ with no test functions ignored"
cat > tests/unit/case.js <<'J'
it('in tests dir', () => {});
J
blocks tests/unit/case.js "tests/unit/case.js:1" "any code file under tests/ is scanned"
echo 'not code' > t/notes.spec.md
allows t/notes.spec.md "non-code extension ignored"
allows t/does-not-exist.test.js "missing file => exit 0"
printf '%s' 'garbage' | bash "$H/check-test-quality.sh" >/dev/null 2>&1; [ $? -eq 0 ] && ok check-test-quality "garbage input fails open" || bad check-test-quality "garbage input"
printf '' | bash "$H/check-test-quality.sh" >/dev/null 2>&1; [ $? -eq 0 ] && ok check-test-quality "empty input fails open" || bad check-test-quality "empty input"
printf '{"tool_input":{}}' | bash "$H/check-test-quality.sh" >/dev/null 2>&1; [ $? -eq 0 ] && ok check-test-quality "no file_path => exit 0" || bad check-test-quality "no file_path"
printf 'it("unterminated", () => {\n  foo(\n' > t/broken.test.js
allows t/broken.test.js "unbalanced/truncated file => no finding (fail open)"
RC=0; printf '{"tool_input":{"file_path":"%s/t/empty.test.js"}}' "$SANDBOX" | MOGGER_CHECK_TESTS=off bash "$H/check-test-quality.sh" >/dev/null 2>&1 || RC=$?
[ "$RC" -eq 0 ] && ok check-test-quality "MOGGER_CHECK_TESTS=off disables" || bad check-test-quality "off switch"
RC=0; printf '{"tool_input":{"file_path":"%s/t/empty.test.js"}}' "$SANDBOX" | PATH="/nonexistent-bin" /bin/bash "$H/check-test-quality.sh" >/dev/null 2>&1 || RC=$?
[ "$RC" -eq 0 ] && ok check-test-quality "no jq/python3 on PATH => fail open" || bad check-test-quality "no-tools fail open (rc=$RC)"

echo "== tests-quality.sh (project-wide report)"
PR="$SANDBOX/proj"; mkdir -p "$PR/src" "$PR/tests" "$PR/node_modules/x"
cat > "$PR/src/cart.js" <<'J'
export const add = (a, b) => a + b;
J
cat > "$PR/src/orders.js" <<'J'
export const order = () => 1;
J
cat > "$PR/src/users.js" <<'J'
export const user = () => 1;
J
cat > "$PR/tests/cart.test.js" <<'J'
it('adds', () => { expect(add(1, 2)).toBe(3); });
it('fake', () => { expect(true).toBe(true); });
it('noop', () => {});
it.only('focus', () => { expect(add(2, 2)).toBe(4); });
it.skip('skipped', () => { expect(add(3, 3)).toBe(6); });
J
cat > "$PR/node_modules/x/bad.test.js" <<'J'
it('ignored', () => {});
J
R=$(bash "$ROOT/scripts/checks/tests-quality.sh" "$PR" 2>&1); RC=$?
[ "$RC" -eq 0 ] && ok tests-quality.sh "always exits 0" || bad tests-quality.sh "exit code $RC"
case "$R" in *"PASS|tests-inventory|1 test files, 3 source files"*) ok tests-quality.sh "inventory counts test vs source files" ;; *) bad tests-quality.sh "inventory: $R" ;; esac
case "$R" in *"FAIL|tests-no-assertions|tests/cart.test.js:3"*) ok tests-quality.sh "empty test reported with file:line" ;; *) bad tests-quality.sh "no-assertions: $R" ;; esac
case "$R" in *"FAIL|tests-tautologies|tests/cart.test.js:2"*) ok tests-quality.sh "tautology reported with file:line" ;; *) bad tests-quality.sh "tautology: $R" ;; esac
case "$R" in *"FAIL|tests-focused|tests/cart.test.js:4"*) ok tests-quality.sh ".only reported" ;; *) bad tests-quality.sh "focused: $R" ;; esac
case "$R" in *"WARN|tests-skipped|tests/cart.test.js:5"*) ok tests-quality.sh "skipped test reported as WARN" ;; *) bad tests-quality.sh "skipped: $R" ;; esac
case "$R" in *"WARN|tests-untested-sources|HEURISTIC: 2 of 3"*) ok tests-quality.sh "untested-source ratio (2 of 3) labelled heuristic" ;; *) bad tests-quality.sh "ratio: $R" ;; esac
case "$R" in *"WARN|tests-unhappy-paths|HEURISTIC"*) ok tests-quality.sh "no error-case test names => WARN" ;; *) bad tests-quality.sh "unhappy: $R" ;; esac
case "$R" in *node_modules*) bad tests-quality.sh "node_modules must be skipped" ;; *) ok tests-quality.sh "node_modules skipped" ;; esac
BADLINES=$(printf '%s\n' "$R" | grep -v -E '^(PASS|WARN|FAIL|SKIP)\|[a-z-]+\|' | head -n 1)
[ -z "$BADLINES" ] && ok tests-quality.sh "every line is LEVEL|check-id|message" || bad tests-quality.sh "malformed line: $BADLINES"
cat >> "$PR/tests/cart.test.js" <<'J'
it('rejects empty input', () => { expect(() => add()).toThrow(); });
J
R=$(bash "$ROOT/scripts/checks/tests-quality.sh" "$PR" 2>&1)
case "$R" in *"PASS|tests-unhappy-paths|1 of 1"*) ok tests-quality.sh "error-case test name => PASS" ;; *) bad tests-quality.sh "unhappy pass: $R" ;; esac
EMPTYP="$SANDBOX/emptyproj"; mkdir -p "$EMPTYP"
R=$(bash "$ROOT/scripts/checks/tests-quality.sh" "$EMPTYP" 2>&1)
case "$R" in SKIP\|tests-inventory\|*) ok tests-quality.sh "empty project => SKIP with reason" ;; *) bad tests-quality.sh "empty: $R" ;; esac
NOTEST="$SANDBOX/notests"; mkdir -p "$NOTEST"; echo 'x=1' > "$NOTEST/a.py"
R=$(bash "$ROOT/scripts/checks/tests-quality.sh" "$NOTEST" 2>&1)
case "$R" in *"WARN|tests-inventory|0 test files vs 1 source"*) ok tests-quality.sh "source but no tests => WARN" ;; *) bad tests-quality.sh "no tests: $R" ;; esac
[ -z "$(cd "$PR" && git status --porcelain 2>/dev/null | grep -v '^??')" ] && ok tests-quality.sh "does not modify tracked files" || bad tests-quality.sh "modified files"

echo "== fix-loop-guard.sh"
cd "$SANDBOX"
STATEF=".claude/state/fixloop.json"
FLERR=""; FLRC=0
fl_fail() {  # fl_fail <command> <error-text>   (PostToolUseFailure)
  jq -n --arg c "$1" --arg e "$2" '{hook_event_name:"PostToolUseFailure",tool_name:"Bash",tool_input:{command:$c},error:$e,is_interrupt:false}' > "$SANDBOX/.payload"
  FLERR=$(bash "$H/fix-loop-guard.sh" < "$SANDBOX/.payload" 2>&1 >"$SANDBOX/.out"); FLRC=$?
}
fl_pass() {  # fl_pass <command> <stdout>       (PostToolUse)
  jq -n --arg c "$1" --arg o "$2" '{hook_event_name:"PostToolUse",tool_name:"Bash",tool_input:{command:$c},tool_response:{stdout:$o,stderr:"",interrupted:false,isImage:false}}' > "$SANDBOX/.payload"
  FLERR=$(bash "$H/fix-loop-guard.sh" < "$SANDBOX/.payload" 2>&1 >"$SANDBOX/.out"); FLRC=$?
}
want() {  # want <rc> <desc>
  if [ "$FLRC" -eq "$1" ]; then ok fix-loop-guard "$2"; else bad fix-loop-guard "$2 (want $1, got $FLRC: $FLERR)"; fi
}
E1=$'Exit code 1\nFAIL src/cart.test.js (12 ms)\n  ● cart > adds item\n    expected 3 received 4 at src/cart.js:42:7\nTests: 1 failed, 4 passed, 5 total'
E1b=$'Exit code 1\nFAIL src/cart.test.js (98 ms)\n  ● cart > adds item\n    expected 3 received 4 at src/cart.js:57:9\nTests: 1 failed, 4 passed, 5 total'
E2=$'Exit code 1\nFAIL src/orders.test.js (9 ms)\n  ● orders > total\nTests: 1 failed, 4 passed, 5 total'
rm -rf .claude

fl_fail "npm test" "$E1"; want 0 "1st failure => allow"
fl_fail "npm test" "$E1b"; want 0 "2nd same failure (other line numbers/timings) => allow"
grep -q '"count":2' "$STATEF" && ok fix-loop-guard "state counts 2 (line numbers/timings normalised)" || bad fix-loop-guard "state: $(cat "$STATEF")"
fl_fail "npm test" "$E1"; want 2 "3rd same failure => exit 2"
case "$FLERR" in *"STOP the fix loop"*) ok fix-loop-guard "message starts STOP the fix loop" ;; *) bad fix-loop-guard "msg: $FLERR" ;; esac
case "$FLERR" in *"hypothesis you have NOT yet verified"*) ok fix-loop-guard "message asks for unverified hypothesis" ;; *) bad fix-loop-guard "hypothesis" ;; esac
case "$FLERR" in *"bash scripts/mogger-rewind.sh list"*) ok fix-loop-guard "message points at mogger-rewind list" ;; *) bad fix-loop-guard "rewind" ;; esac
case "$FLERR" in *"revert that edit"*"ask the user"*) ok fix-loop-guard "message: revert last edit, ask the user" ;; *) bad fix-loop-guard "revert/ask" ;; esac
case "$FLERR" in *"re-read"*|*"Re-read"*) ok fix-loop-guard "message: re-read the failing test" ;; *) bad fix-loop-guard "reread" ;; esac
fl_fail "npm test" "$E1"; want 2 "4th failure keeps blocking"

echo "-- pass resets"
fl_pass "npm test" "Tests: 5 passed, 5 total"; want 0 "pass => exit 0"
[ ! -f "$STATEF" ] && ok fix-loop-guard "pass removes state" || bad fix-loop-guard "state survived a pass"
fl_fail "npm test" "$E1"; fl_fail "npm test" "$E1"; want 0 "after pass: 2 failures allowed again"
fl_fail "npm test" "$E1"; want 2 "after pass: 3rd blocks (count restarted)"

echo "-- different signature resets"
rm -f "$STATEF"
fl_fail "npm test" "$E1"; fl_fail "npm test" "$E1"
fl_fail "npm test" "$E2"; want 0 "different failing test => allow"
grep -q '"count":1' "$STATEF" && ok fix-loop-guard "different signature restarts at 1" || bad fix-loop-guard "state: $(cat "$STATEF")"
fl_fail "npm test" "$E1"; want 0 "back to first signature => count 1, allow"
rm -f "$STATEF"
fl_fail "npm test" "$E1"; fl_fail "npm test" "$E1"
fl_fail "pnpm test" "$E1"; want 0 "same error but different command => different signature"

echo "-- pass of a different command does not hide the loop"
rm -f "$STATEF"
fl_fail "npm test" "$E1"; fl_fail "npm test" "$E1"
fl_pass "npm run lint" "all good"
fl_fail "npm test" "$E1"; want 2 "lint pass between test failures does not reset"

echo "-- threshold env"
rm -f "$STATEF"
FLRC=0; jq -n --arg e "$E1" '{hook_event_name:"PostToolUseFailure",tool_input:{command:"npm test"},error:$e}' > "$SANDBOX/.payload"
MOGGER_MAX_FIX_ATTEMPTS=2 bash "$H/fix-loop-guard.sh" < "$SANDBOX/.payload" >/dev/null 2>&1; a=$?
MOGGER_MAX_FIX_ATTEMPTS=2 bash "$H/fix-loop-guard.sh" < "$SANDBOX/.payload" >/dev/null 2>&1; b=$?
[ "$a" -eq 0 ] && [ "$b" -eq 2 ] && ok fix-loop-guard "MOGGER_MAX_FIX_ATTEMPTS=2 blocks on 2nd" || bad fix-loop-guard "threshold 2 (a=$a b=$b)"
rm -f "$STATEF"
for i in 1 2 3 4; do MOGGER_MAX_FIX_ATTEMPTS=5 bash "$H/fix-loop-guard.sh" < "$SANDBOX/.payload" >/dev/null 2>&1; c=$?; done
[ "$c" -eq 0 ] && ok fix-loop-guard "MOGGER_MAX_FIX_ATTEMPTS=5 still allows 4th" || bad fix-loop-guard "threshold 5"
MOGGER_MAX_FIX_ATTEMPTS=5 bash "$H/fix-loop-guard.sh" < "$SANDBOX/.payload" >/dev/null 2>&1; [ $? -eq 2 ] && ok fix-loop-guard "MOGGER_MAX_FIX_ATTEMPTS=5 blocks 5th" || bad fix-loop-guard "threshold 5 block"
rm -f "$STATEF"
for i in 1 2 3; do MOGGER_MAX_FIX_ATTEMPTS=abc bash "$H/fix-loop-guard.sh" < "$SANDBOX/.payload" >/dev/null 2>&1; c=$?; done
[ "$c" -eq 2 ] && ok fix-loop-guard "non-numeric threshold falls back to 3" || bad fix-loop-guard "bad threshold"

echo "-- disabled / fail-open"
rm -f "$STATEF"
for i in 1 2 3 4; do MOGGER_FIX_LOOP_GUARD=off bash "$H/fix-loop-guard.sh" < "$SANDBOX/.payload" >/dev/null 2>&1; c=$?; done
[ "$c" -eq 0 ] && [ ! -f "$STATEF" ] && ok fix-loop-guard "MOGGER_FIX_LOOP_GUARD=off => allow, no state" || bad fix-loop-guard "off switch"
for junk in 'garbage' '' '{' '[1,2,3]' '{"tool_input":"x"}' '{"tool_input":{"command":123}}' '{"tool_input":{"command":"npm test"},"error":null}' 'null'; do
  printf '%s' "$junk" | bash "$H/fix-loop-guard.sh" >/dev/null 2>&1; r=$?
  [ "$r" -eq 0 ] && ok fix-loop-guard "odd input fails open: $(printf '%s' "$junk" | cut -c1-30)" || bad fix-loop-guard "odd input rc=$r: $junk"
done
rm -f "$STATEF"
printf '{"tool_input":{"command":"npm test"},"error":"Exit code 1\\nFAIL x"}' | PATH="/nonexistent-bin" /bin/bash "$H/fix-loop-guard.sh" >/dev/null 2>&1
[ $? -eq 0 ] && ok fix-loop-guard "no jq/python3 => fail open" || bad fix-loop-guard "no-tools"
echo 'not json {{{' > "$STATEF"
fl_fail "npm test" "$E1"; want 0 "corrupt state file => treated as fresh"
mkdir -p "$SANDBOX/ro" && ( cd "$SANDBOX/ro" && touch .claude 2>/dev/null; bash "$H/fix-loop-guard.sh" < "$SANDBOX/.payload" >/dev/null 2>&1 ); [ $? -eq 0 ] && ok fix-loop-guard "unwritable state dir => fail open" || bad fix-loop-guard "unwritable state"

echo "-- only test/build/lint commands, and only real failures"
rm -f "$STATEF"
for i in 1 2 3 4; do fl_fail "ls -la" "$E1"; done; want 0 "non-test command never counted"
[ ! -f "$STATEF" ] && ok fix-loop-guard "non-test command writes no state" || bad fix-loop-guard "state for ls"
for c in "npm test" "pnpm test" "yarn test" "npm run test" "npx vitest run" "jest --ci" "pytest -x tests/" "python -m pytest" "go test ./..." "cargo test" "make test" "tsc --noEmit" "npm run build" "cd app && npm test" "npx eslint src"; do
  rm -f "$STATEF"; fl_fail "$c" "$E1"
  [ -f "$STATEF" ] && ok fix-loop-guard "recognised: $c" || bad fix-loop-guard "not recognised: $c"
done
for c in "echo npm test" "cat test.txt" "git status" "npm install" "node server.js" "testify"; do
  rm -f "$STATEF"; fl_fail "$c" "$E1"
  [ ! -f "$STATEF" ] && ok fix-loop-guard "ignored: $c" || bad fix-loop-guard "wrongly tracked: $c"
done
rm -f "$STATEF"
for i in 1 2 3; do fl_fail "npm test" $'Exit code 127\nnpm: command not found'; done; want 0 "exit 127 (command not found) is not a test failure"
[ ! -f "$STATEF" ] && ok fix-loop-guard "exit 127 writes no state" || bad fix-loop-guard "127 state"
jq -n --arg e "$E1" '{hook_event_name:"PostToolUseFailure",tool_input:{command:"npm test"},error:$e,is_interrupt:true}' > "$SANDBOX/.payload"
for i in 1 2 3; do bash "$H/fix-loop-guard.sh" < "$SANDBOX/.payload" >/dev/null 2>&1; done
[ ! -f "$STATEF" ] && ok fix-loop-guard "interrupted run ignored" || bad fix-loop-guard "interrupt state"
for i in 1 2 3; do fl_fail "npm test" "Something odd with no exit code line"; done; want 0 "failure payload without exit code => undeterminable => nothing"
[ ! -f "$STATEF" ] && ok fix-loop-guard "undeterminable writes no state" || bad fix-loop-guard "undeterminable state"
fl_fail "npm test" $'Command timed out after 2m 0s'; [ -f "$STATEF" ] && ok fix-loop-guard "timeout counts as a failure" || bad fix-loop-guard "timeout"

echo "-- exit-0 run with failure output (piped: npm test | tail)"
rm -f "$STATEF"
fl_pass "npm test 2>&1 | tail -5" $'FAIL src/a.test.js\nTests: 2 failed, 3 passed'; want 0 "piped failure recorded, allowed"
[ -f "$STATEF" ] && ok fix-loop-guard "piped failure signature counted" || bad fix-loop-guard "piped"
fl_pass "npm test 2>&1 | tail -5" $'FAIL src/a.test.js\nTests: 2 failed, 3 passed'
fl_pass "npm test 2>&1 | tail -5" $'FAIL src/a.test.js\nTests: 2 failed, 3 passed'; want 2 "piped failure 3x => block"
rm -f "$STATEF"
fl_pass "npm test" "Tests: 0 failed, 5 passed"; [ ! -f "$STATEF" ] && ok fix-loop-guard "'0 failed' is a pass" || bad fix-loop-guard "0 failed"
jq -n '{hook_event_name:"PostToolUse",tool_input:{command:"npm test"},tool_response:{stdout:"boom",exit_code:1}}' > "$SANDBOX/.payload"
bash "$H/fix-loop-guard.sh" < "$SANDBOX/.payload" >/dev/null 2>&1; [ -f "$STATEF" ] && ok fix-loop-guard "explicit tool_response.exit_code!=0 honoured" || bad fix-loop-guard "exit_code field"
jq -n '{hook_event_name:"PostToolUse",tool_input:{command:"npm test"},tool_response:"just a string"}' > "$SANDBOX/.payload"
rm -f "$STATEF"; bash "$H/fix-loop-guard.sh" < "$SANDBOX/.payload" >/dev/null 2>&1; [ $? -eq 0 ] && ok fix-loop-guard "string tool_response handled" || bad fix-loop-guard "string response"

echo "-- whack-a-mole"
rm -f "$STATEF"
W1=$'Exit code 1\nFAIL src/a.test.js\nTests: 1 failed, 9 passed, 10 total'
W3=$'Exit code 1\nFAIL src/b.test.js\nTests: 3 failed, 7 passed, 10 total'
fl_fail "npm test" "$W1"
FLERR=$(bash -c 'cd "$1"; jq -n --arg e "$2" "{hook_event_name:\"PostToolUseFailure\",tool_input:{command:\"npm test\"},error:\$e}" | bash "$3"' _ "$SANDBOX" "$W3" "$H/fix-loop-guard.sh" 2>&1 >"$SANDBOX/.out"); FLRC=$?
want 0 "failing count 1 -> 3 => warn, exit 0"
case "$FLERR" in *whack-a-mole*"1 to 3"*) ok fix-loop-guard "warning names the increase (1 to 3)" ;; *) bad fix-loop-guard "warn text: $FLERR" ;; esac
grep -q additionalContext "$SANDBOX/.out" && ok fix-loop-guard "warning also emitted as additionalContext" || bad fix-loop-guard "no additionalContext"
W4=$'Exit code 1\nFAIL src/c.test.js\nTests: 5 failed, 5 passed, 10 total'
fl_fail "npm test" "$W4"
case "$FLERR" in *whack-a-mole*) bad fix-loop-guard "warned twice" ;; *) ok fix-loop-guard "whack-a-mole warns only once" ;; esac
rm -f "$STATEF"
fl_fail "npm test" "$W3"; fl_fail "npm test" "$W1"
case "$FLERR" in *whack-a-mole*) bad fix-loop-guard "decrease must not warn" ;; *) ok fix-loop-guard "decreasing failure count does not warn" ;; esac

echo "-- speed"
rm -f "$STATEF"; jq -n --arg e "$E1" '{hook_event_name:"PostToolUseFailure",tool_input:{command:"npm test"},error:$e}' > "$SANDBOX/.payload"
T0=$(date +%s)
for i in 1 2 3 4 5 6 7 8 9 10; do bash "$H/fix-loop-guard.sh" < "$SANDBOX/.payload" >/dev/null 2>&1; rm -f "$STATEF"; done
T1=$(date +%s)
[ $((T1 - T0)) -le 3 ] && ok fix-loop-guard "10 runs in <=3s (well under 150ms each on this box)" || bad fix-loop-guard "slow: $((T1 - T0))s for 10 runs"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
