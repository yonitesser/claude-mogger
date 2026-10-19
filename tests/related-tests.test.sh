#!/usr/bin/env bash
# Tests for hooks/scripts/related-tests.sh: which tests to run for the files that changed.
# Run: bash tests/related-tests.test.sh   (temp sandbox, no network, runs no test runner)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
R="$ROOT/hooks/scripts/related-tests.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
SB=$(mktemp -d); trap 'rm -rf "$SB"' EXIT
unset MOGGER_RELATED_TESTS
export CLAUDE_PROJECT_DIR="$SB"
# a stand-in "pytest" so the python case works on a box without it
mkdir -p "$SB/fake"; : > "$SB/fake/pytest.py"; export PYTHONPATH="$SB/fake"

# fresh git project in a new dir: proj <name>
proj() { P="$SB/$1"; mkdir -p "$P"; cd "$P" || exit 1; git init -q -b main . 2>/dev/null || { git init -q .; git checkout -q -b main; }; export CLAUDE_PROJECT_DIR="$P"; }
commit() { git add -A; git -c user.email=a@b -c user.name=n commit -qm i; }
# expect <scope> <needle-in-command> <desc> [files...]
expect() {
  local scope="$1" needle="$2" desc="$3" out; shift 3
  out=$(bash "$R" "$@" 2>&1)
  case "$out" in "scope: $scope"$'\n'"command: "*) ;; *) bad "$desc (got: $out)"; return ;; esac
  case "$out" in *"$needle"*) ;; *) bad "$desc (no '$needle' in: $out)"; return ;; esac
  ok "$desc"
}
lacks() { case "$(bash "$R" "$3" 2>&1)" in *"$2"*) bad "$1" ;; *) ok "$1" ;; esac; }

# --- jest / vitest: the project's own tool
proj jest; echo '{"scripts":{"test":"jest"},"devDependencies":{"jest":"1"}}' > package.json
mkdir src; echo 'x' > src/a.js; commit
expect affected "jest --findRelatedTests src/a.js" "jest: findRelatedTests on the changed file" src/a.js
proj vitest; echo '{"scripts":{"test":"vitest"},"devDependencies":{"vitest":"1"}}' > package.json
mkdir src; echo 'x' > src/a.ts; commit
expect affected "vitest related --run src/a.ts" "vitest: related on the changed file" src/a.ts
expect full "npm test" "a changed package.json runs everything" package.json src/a.ts

# --- python: name and import match
proj py; printf '[pytest]\n' > pytest.ini; mkdir src tests
echo 'def a(): pass' > src/foo.py; echo 'def b(): pass' > src/bar.py; echo 'def c(): pass' > src/lonely.py
echo 'from src.foo import a' > tests/test_foo.py; echo 'from src.bar import b' > tests/test_bar.py; echo hi > README.md; commit
expect affected "tests/test_foo.py" "python: finds the test that imports the file" src/foo.py
lacks "python: leaves the other tests out" "test_bar" src/foo.py
expect affected "tests/test_foo.py" "python: a changed test file runs itself" tests/test_foo.py
expect full "pytest -x -q" "python: a file with no test runs everything" src/lonely.py
expect full "pytest -x -q" "python: one untested file among tested ones runs everything" src/foo.py src/lonely.py
expect full "pytest -x -q" "python: a docs change runs everything" README.md src/foo.py
echo '# x' >> src/foo.py
expect affected "tests/test_foo.py" "no arguments: reads git changes"
expect full "pytest -x -q" "deleted file only: runs everything (nothing left to map)" src/gone.py

# --- go: the package folder
proj go; echo 'module m' > go.mod; mkdir pkg; echo 'package pkg' > pkg/a.go; echo 'package pkg' > pkg/a_test.go; commit
expect affected "go test ./pkg" "go: tests the package of the changed file" pkg/a.go

# --- bash test suites (this repo's shape), awkward names
proj sh; mkdir tests "my dir"; echo 'run foo.sh' > tests/foo.test.sh; echo 1 > foo.sh; echo 1 > "my dir/odd name.sh"; echo 'odd name.sh' > tests/odd.test.sh; commit
expect affected "bash tests/foo.test.sh" "bash: finds the suite that names the script" foo.sh
expect affected "odd.test.sh" "bash: a file name with a space still maps" "my dir/odd name.sh"
# index files are imported by their folder name
proj idx; echo '{"devDependencies":{"mocha":"1"},"scripts":{"test":"mocha"}}' > package.json; mkdir -p lib/widget tests; echo 1 > lib/widget/index.js
echo "require('../lib/widget')" > tests/widget.test.js; commit
expect affected "tests/widget.test.js" "index.js is matched by its folder name" lib/widget/index.js

# --- toggle
proj tog; echo '{"scripts":{"test":"jest"},"devDependencies":{"jest":"1"}}' > package.json; mkdir src; echo x > src/a.js; commit
MOGGER_RELATED_TESTS=off bash "$R" src/a.js | grep -q '^scope: full' && ok "env var off: always full" || bad "env var off"
mkdir -p .claude; echo '{"related-tests":"off"}' > .claude/mogger.json
bash "$R" src/a.js | grep -q '^scope: full' && ok "toggle file off: always full" || bad "toggle file off"
grep -q '^related-tests	MOGGER_RELATED_TESTS	standard' "$ROOT/hooks/guards.tsv" && ok "catalog has the related-tests row" || bad "catalog row"

# --- no test command, no git
proj bare; echo x > a.py
bash "$R" a.py >/dev/null 2>&1; [ $? -eq 1 ] && ok "no test command: exit 1, no output" || bad "no test command"
proj nogit-edits; rm -rf .git; echo '{"devDependencies":{"jest":"1"},"scripts":{"test":"jest"}}' > package.json; mkdir -p .claude/state src; echo x > src/a.js
printf 'C src/a.js\n' > .claude/state/edits.log
expect affected "src/a.js" "no git: reads .claude/state/edits.log"
proj clean; echo '{"devDependencies":{"jest":"1"},"scripts":{"test":"jest"}}' > package.json; commit
expect full "npm test" "nothing changed: runs everything"

# --- the hint on a bare full-suite run
H="$ROOT/hooks/scripts/hint-noisy-bash.sh"
hint() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" | bash "$H" 2>/dev/null; }
hint "npm test" | jq -e '.hookSpecificOutput.additionalContext | contains("related-tests.sh")' >/dev/null 2>&1 && ok "hint: a bare npm test points at related-tests.sh (valid JSON)" || bad "hint missing or bad JSON"
case "$(hint 'git log')" in *related-tests*) bad "hint: git log got the test hint" ;; *) ok "hint: other noisy commands are untouched" ;; esac
case "$(MOGGER_RELATED_TESTS=off hint 'npm test')" in *related-tests*) bad "hint: shown with toggle off" ;; *) ok "hint: silent about it with the toggle off" ;; esac

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"; [ "$FAIL" -eq 0 ]
