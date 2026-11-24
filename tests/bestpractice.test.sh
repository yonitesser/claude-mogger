#!/usr/bin/env bash
# Best-practice batch (Batch 14): lockfile-guard, syntax-check, danger-guard git additions.
# Run: bash tests/bestpractice.test.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
H="$ROOT/hooks/scripts"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
SB=$(mktemp -d); trap 'rm -rf "$SB"' EXIT
export CLAUDE_PROJECT_DIR="$SB"
cd "$SB" && git init -q -b work . 2>/dev/null
unset MOGGER_LOCKFILE_GUARD MOGGER_CHECK_SYNTAX MOGGER_DANGER_GUARD MOGGER_HEADLESS CLAUDE_CODE_ENTRYPOINT

edit_json() { printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$1"; }
bash_json() { python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$1"; }
run() { OUT=$(printf '%s' "$2" | bash "$H/$1" 2>"$SB/err"); RC=$?; ERR=$(cat "$SB/err"); }
is_ask() { printf '%s' "$OUT" | jq -e '.hookSpecificOutput.permissionDecision=="ask"' >/dev/null 2>&1; }

echo "== lockfile-guard"
run lockfile-guard.sh "$(edit_json "$SB/package-lock.json")"
[ $RC -eq 0 ] && is_ask && ok "package-lock.json: asks by default" || bad "default ask rc=$RC out=$OUT"
for f in yarn.lock pnpm-lock.yaml poetry.lock Cargo.lock go.sum Gemfile.lock uv.lock composer.lock; do
  run lockfile-guard.sh "$(edit_json "$SB/sub/$f")"
  [ $RC -eq 0 ] && is_ask && ok "$f: asks" || bad "$f not caught"
done
run lockfile-guard.sh "$(edit_json "$SB/src/app.js")"
[ $RC -eq 0 ] && [ -z "$OUT" ] && ok "normal source file: silent" || bad "app.js not silent"
run lockfile-guard.sh "$(edit_json "$SB/package.json")"
[ $RC -eq 0 ] && [ -z "$OUT" ] && ok "package.json (not a lockfile): silent" || bad "package.json not silent"
run lockfile-guard.sh "$(edit_json "$SB/tests/fixtures/package-lock.json")"
[ $RC -eq 0 ] && [ -z "$OUT" ] && ok "lockfile under tests/fixtures: silent" || bad "fixture lockfile flagged"
MOGGER_HEADLESS=on run lockfile-guard.sh "$(edit_json "$SB/yarn.lock")"
[ $RC -eq 2 ] && ok "no prompt available: blocks" || bad "headless rc=$RC"
MOGGER_LOCKFILE_GUARD=on run lockfile-guard.sh "$(edit_json "$SB/yarn.lock")"
[ $RC -eq 2 ] && ok "state on: blocks" || bad "on rc=$RC"
MOGGER_LOCKFILE_GUARD=off run lockfile-guard.sh "$(edit_json "$SB/yarn.lock")"
[ $RC -eq 0 ] && [ -z "$OUT" ] && ok "state off: allows" || bad "off rc=$RC"
MOGGER_LOCKFILE_GUARD=zzz run lockfile-guard.sh "$(edit_json "$SB/yarn.lock")"
[ $RC -eq 0 ] && is_ask && ok "bad value: default (ask)" || bad "bad value rc=$RC"
run lockfile-guard.sh '{"tool_name":"Edit","tool_input":{}}'
[ $RC -eq 0 ] && [ -z "$OUT" ] && ok "no file path: fails open" || bad "no path rc=$RC"

echo "== syntax-check"
post_json() { printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$1"; }
printf 'def f(:\n  pass\n' > bad.py;        printf 'x = 1\nprint(x)\n' > good.py
printf 'if then fi done\n' > bad.sh;        printf 'echo hi\n' > good.sh
printf '{"a": 1,}\n' > bad.json;            printf '{"a": 1}\n' > good.json
printf 'function (( {\n' > bad.js;          printf 'const a = 1;\nconsole.log(a);\n' > good.js
printf '{"compilerOptions": {/* c */ "strict": true,},}\n' > tsconfig.json
printf 'import x from "y";\nexport const z = x;\n' > esm.js
for f in bad.py bad.sh bad.json bad.js; do
  run check-syntax.sh "$(post_json "$SB/$f")"
  [ $RC -eq 0 ] && printf '%s' "$OUT" | jq -e '.hookSpecificOutput.additionalContext|test("Syntax error")' >/dev/null 2>&1 && ok "$f: warns (exit 0)" || bad "$f not caught rc=$RC out=$OUT"
done
for f in good.py good.sh good.json good.js esm.js tsconfig.json; do
  run check-syntax.sh "$(post_json "$SB/$f")"
  [ $RC -eq 0 ] && [ -z "$OUT" ] && ok "$f: silent" || bad "$f false alarm: $OUT"
done
[ ! -d __pycache__ ] && ok "python check writes no __pycache__" || bad "left __pycache__"
printf 'x' > notes.txt; run check-syntax.sh "$(post_json "$SB/notes.txt")"
[ $RC -eq 0 ] && [ -z "$OUT" ] && ok "other file types: silent" || bad "txt not silent"
run check-syntax.sh "$(post_json "$SB/missing.py")"
[ $RC -eq 0 ] && [ -z "$OUT" ] && ok "missing file: fails open" || bad "missing rc=$RC"
MOGGER_CHECK_SYNTAX=off run check-syntax.sh "$(post_json "$SB/bad.py")"
[ $RC -eq 0 ] && [ -z "$OUT" ] && ok "MOGGER_CHECK_SYNTAX=off: silent" || bad "off not silent"
printf 'def f(:\n' > 'we"ird.py'; run check-syntax.sh "$(python3 -c 'import json,sys;print(json.dumps({"tool_input":{"file_path":sys.argv[1]}}))' "$SB/we\"ird.py")"
printf '%s' "$OUT" | jq -e . >/dev/null 2>&1 && ok "odd file name: output is still valid JSON" || bad "bad JSON: $OUT"

echo "== danger-guard: git history and forced checkout"
dg() { run danger-guard.sh "$(bash_json "$1")"; }
# built from parts so this file is not itself a risky command line
G="gi""t"
for c in "$G stash drop" "$G stash clear" "$G stash drop stash@{1}" "$G reflog expire --expire=now --all" "$G reflog delete HEAD@{2}" \
         "$G gc --prune=now" "$G filter-branch --tree-filter x HEAD" "$G update-ref -d refs/heads/x" \
         "$G checkout -f main" "$G switch --discard-changes main" "$G -C sub checkout --force x"; do
  dg "$c"; [ $RC -eq 2 ] && ok "blocks: $c" || bad "not blocked: $c (rc=$RC)"
done
for c in "$G stash" "$G stash list" "$G stash pop" "$G stash push -m wip" "$G gc" "$G reflog" "$G reflog show" "$G checkout -b feat" \
         "$G checkout main" "$G switch main" "$G update-ref HEAD HEAD" "$G status && ls"; do
  dg "$c"; [ $RC -eq 0 ] && ok "allows: $c" || bad "false block: $c"
done
dg "echo 'then run $G stash drop to lose it'"; [ $RC -eq 0 ] && ok "text that only mentions it passes" || bad "prose blocked"
MOGGER_DANGER_GUARD=ask run danger-guard.sh "$(bash_json "$G stash clear")"
[ $RC -eq 0 ] && is_ask && ok "ask state: prompt, not block" || bad "ask state rc=$RC"

echo "== danger-guard: a long && chain cannot hide a danger (deny rules stop checking past 50 subcommands)"
CH=$(python3 -c 'print(" && ".join(["true"]*80) + " && " + "r"+"m -r"+"f ~")')
dg "$CH"; [ $RC -eq 2 ] && ok "80-step chain still blocked" || bad "chain bypass rc=$RC"
CH=$(python3 -c 'print(" && ".join(["true"]*80) + " && " + "gi"+"t stash clear")')
dg "$CH"; [ $RC -eq 2 ] && ok "80-step chain: git stash clear still blocked" || bad "chain bypass 2 rc=$RC"

echo "== catalog"
grep -qP '^lockfile-guard\tMOGGER_LOCKFILE_GUARD\tsafety\task\task\t' "$ROOT/hooks/guards.tsv" && ok "lockfile-guard row" || bad "no lockfile row"
grep -qP '^syntax-check\tMOGGER_CHECK_SYNTAX\tstandard\ton\ton\t' "$ROOT/hooks/guards.tsv" && ok "syntax-check row" || bad "no syntax row"
grep -q 'lockfile-guard.sh' "$ROOT/hooks/hooks.json" && grep -q 'check-syntax.sh' "$ROOT/hooks/hooks.json" && ok "both hooks are in hooks.json" || bad "hooks.json missing"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"; [ "$FAIL" -eq 0 ]
