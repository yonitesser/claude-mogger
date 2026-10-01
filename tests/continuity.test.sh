#!/usr/bin/env bash
# Tests for context continuity (precompact-save.sh, handoff-context.sh),
# scripts/checks/deploy.sh and ship-check.sh module aggregation.
# Run: bash tests/continuity.test.sh   (temp git sandbox, no network)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
H="$ROOT/hooks/scripts"; DEP="$ROOT/scripts/checks/deploy.sh"; SHIP="$ROOT/scripts/ship-check.sh"
PASS=0; FAIL=0
BASE=$(mktemp -d)
trap 'rm -rf "$BASE"' EXIT

ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
expect() {  # expect <desc> <command...>  passes when the command succeeds
  local d="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi
}
eq() { [ "$1" = "$2" ]; }
has() { grep -q -F -e "$2" "$1"; }
hasnt() { ! grep -q -F -e "$2" "$1"; }
git_q() { git -c user.email=t@t -c user.name=t "$@"; }

newproj() {
  rm -rf "$BASE/p"; mkdir -p "$BASE/p"; cd "$BASE/p" || exit 1
  git init -q . 2>/dev/null
  printf '# Tasks\n- [x] set up repo\n- [x] add login\n- [ ] add search page\n- [ ] add export\n- [ ] add billing\n- [ ] add admin\nBLOCKED: waiting on API key from client\n\n## Assumptions\n- UNVERIFIED: the client uses Postgres 14\n- Verified: node 20 (source: package.json)\n' > TASKS.md
  printf 'hello\n' > app.txt
  git add -A; git_q commit -q -m "first commit" ; echo more >> app.txt; git_q commit -q -am "second commit"
}
save() { printf '%s' "${1:-{\"trigger\":\"auto\"\}}" | CLAUDE_PROJECT_DIR="$BASE/p" bash "$H/precompact-save.sh"; }
HF() { printf '%s' "$BASE/p/.claude/state/handoff.md"; }

echo "== precompact-save.sh: content from real state"
newproj
printf 'uncommitted\n' > wip.txt; echo edit >> app.txt
mkdir -p .claude/state
printf '{"status":"pass","scope":"full"}' > .claude/state/last_test_result.json
printf '{"ok":true,"url":"http://127.0.0.1:3000","status":"200"}' > .claude/state/smoke.json
cat > DECISIONS.md <<'D'
## #1 Use SQLite
- Why: one user, file backup
- Status: active
## #2 Use Mongo
- Why: none
- Status: superseded-by #1
D
git update-ref refs/mogger/checkpoints/20260101-000000-001 HEAD
save '{"trigger":"manual","transcript_path":"/nope","custom_instructions":true}'; RC=$?
expect "exits 0" eq "$RC" 0
expect "handoff.md created" test -s "$(HF)"
expect "says 2 done, 4 open" has "$(HF)" "2 done, 4 open"
expect "next open task 1" has "$(HF)" "add search page"
expect "next open task 3" has "$(HF)" "add billing"
expect "only next 3 (4th absent)" hasnt "$(HF)" "add admin"
expect "BLOCKED line included" has "$(HF)" "BLOCKED: waiting on API key from client"
expect "git status file wip.txt" has "$(HF)" "wip.txt"
expect "git status file app.txt" has "$(HF)" "app.txt"
expect ".claude/ not listed as touched" hasnt "$(HF)" "?? .claude"
expect "git log shows commit" has "$(HF)" "second commit"
expect "git log shows first commit" has "$(HF)" "first commit"
expect "checkpoint id present" has "$(HF)" "20260101-000000-001"
expect "test marker result" has "$(HF)" "status 'pass' scope 'full'"
expect "smoke result" has "$(HF)" "ok=true"
expect "smoke url" has "$(HF)" "http://127.0.0.1:3000"
expect "active decision shown" has "$(HF)" "#1 Use SQLite"
expect "superseded decision hidden" hasnt "$(HF)" "Use Mongo"
expect "UNVERIFIED assumption listed" has "$(HF)" "UNVERIFIED: the client uses Postgres 14"
expect "verified assumption not copied" hasnt "$(HF)" "node 20"
expect "trigger recorded from hook input" has "$(HF)" "compaction: manual"
expect "transcript path never copied" hasnt "$(HF)" "/nope"
expect "no stdout from hook" test -z "$(save)"
expect "no temp file left behind" bash -c "! ls '$BASE/p/.claude/state/' | grep -q 'tmp'"

echo "== precompact-save.sh: edge cases"
newproj
printf 'ignore me\n' > REVIEW.md
save >/dev/null
expect "no tests marker says no recorded run" has "$(HF)" "tests: no recorded run"
expect "no smoke marker says no recorded run" has "$(HF)" "smoke: no recorded run"
expect "no DECISIONS.md: no decisions section" hasnt "$(HF)" "Active decisions"
expect "no checkpoint stated plainly" has "$(HF)" "no mogger checkpoint yet"
printf -- '- [ ] fix the login redirect\nVERDICT: NOT READY - missing test\n' > REVIEW.md
save >/dev/null
expect "open review note included" has "$(HF)" "NOT READY - missing test"
expect "open review checkbox included" has "$(HF)" "fix the login redirect"
newproj; save 'garbage {{{ not json' ; RC=$?
expect "garbage stdin: exit 0" eq "$RC" 0
expect "garbage stdin: handoff still written" has "$(HF)" "2 done, 4 open"
expect "garbage stdin: no trigger claimed" hasnt "$(HF)" "compaction:"
newproj; save '' ; RC=$?
expect "empty stdin: exit 0" eq "$RC" 0
# atomic: an existing handoff is replaced whole
printf 'OLDCONTENT\n' > .claude/state/handoff.md; save >/dev/null
expect "existing handoff replaced" hasnt "$(HF)" "OLDCONTENT"
# read-only state dir -> fails open
rm -rf .claude; mkdir -p .claude; : > .claude/state
save >/dev/null; RC=$?
expect "unwritable state dir: exit 0" eq "$RC" 0
rm -f .claude/state
# no git, with TASKS.md
rm -rf "$BASE/ng"; mkdir -p "$BASE/ng"; cd "$BASE/ng"
printf -- '- [ ] only task\n' > TASKS.md
printf '{}' | CLAUDE_PROJECT_DIR="$BASE/ng" bash "$H/precompact-save.sh"; RC=$?
expect "no git: exit 0" eq "$RC" 0
expect "no git: handoff written" test -s "$BASE/ng/.claude/state/handoff.md"
expect "no git: says not a git repository" has "$BASE/ng/.claude/state/handoff.md" "not a git repository"
expect "no git: still has tasks" has "$BASE/ng/.claude/state/handoff.md" "0 done, 1 open"
# nothing to report: no git, no TASKS.md -> writes nothing
rm -rf "$BASE/empty"; mkdir -p "$BASE/empty"; cd "$BASE/empty"
printf '{}' | CLAUDE_PROJECT_DIR="$BASE/empty" bash "$H/precompact-save.sh"; RC=$?
expect "empty dir: exit 0" eq "$RC" 0
expect "empty dir: nothing written" test ! -e "$BASE/empty/.claude"
# opt-out
newproj; printf '{}' | MOGGER_HANDOFF=off CLAUDE_PROJECT_DIR="$BASE/p" bash "$H/precompact-save.sh"
expect "MOGGER_HANDOFF=off writes nothing" test ! -e "$(HF)"
# speed
newproj; S=$(date +%s); for i in 1 2 3 4 5; do save >/dev/null; done; E=$(date +%s)
expect "5 saves in under 5s (fast)" test $((E - S)) -le 5

echo "== handoff-context.sh"
newproj; save >/dev/null
export CLAUDE_PROJECT_DIR="$BASE/p"
OUT=$(bash "$H/handoff-context.sh"); RC=$?
expect "exit 0" eq "$RC" 0
expect "prints age prefix first" bash -c "printf '%s' '$OUT' | head -1 | grep -q 'Handoff saved'"
expect "fresh file shows minutes" bash -c "printf '%s' '$OUT' | head -1 | grep -q ' min ago'"
expect "prints handoff body" bash -c "printf '%s' \"\$1\" | grep -q 'add search page'" _ "$OUT"
# sourced function
OUT2=$(bash -c "source '$H/handoff-context.sh'; handoff_context")
expect "sourced function works" bash -c "printf '%s' \"\$1\" | grep -q 'Handoff saved'" _ "$OUT2"
# age cutoff: 100 hours old (touch -t works on GNU and BSD)
OLD=$(date -u -d '100 hours ago' +%Y%m%d%H%M 2>/dev/null || date -u -v-100H +%Y%m%d%H%M 2>/dev/null)
if [ -n "$OLD" ]; then
  touch -t "$OLD" "$(HF)"
  expect "older than 72h prints nothing" test -z "$(bash "$H/handoff-context.sh")"
  expect "MOGGER_HANDOFF_MAX_AGE_HOURS=200 shows it" test -n "$(MOGGER_HANDOFF_MAX_AGE_HOURS=200 bash "$H/handoff-context.sh")"
  expect "age prefix in hours" bash -c "MOGGER_HANDOFF_MAX_AGE_HOURS=200 bash '$H/handoff-context.sh' | head -1 | grep -q '100 h ago'"
  expect "bad max-age value falls back to 72" test -z "$(MOGGER_HANDOFF_MAX_AGE_HOURS=abc bash "$H/handoff-context.sh")"
else
  for i in 1 2 3 4; do ok "skipped (no date arithmetic on this box)"; done
fi
# 60 line cap
touch "$(HF)"; i=0; : > "$(HF)"; while [ $i -lt 100 ]; do echo "line $i" >> "$(HF)"; i=$((i+1)); done
N=$(bash "$H/handoff-context.sh" | wc -l | tr -d ' ')
expect "capped near 60 lines (<=62)" test "$N" -le 62
expect "truncation notice shown" bash -c "bash '$H/handoff-context.sh' | grep -q truncated"
expect "line 59 kept" bash -c "bash '$H/handoff-context.sh' | grep -q 'line 59'"
expect "line 60 cut" bash -c "! bash '$H/handoff-context.sh' | grep -q 'line 60'"
rm -f "$(HF)"
expect "missing file prints nothing" test -z "$(bash "$H/handoff-context.sh")"
: > "$(HF)"
expect "empty file prints nothing" test -z "$(bash "$H/handoff-context.sh")"
expect "explicit missing path prints nothing" test -z "$(bash "$H/handoff-context.sh" /no/such/file)"
bash "$H/handoff-context.sh" /no/such/file; RC=$?
expect "missing path exits 0" eq "$RC" 0
unset CLAUDE_PROJECT_DIR

echo "== packaging"
expect "precompact-save.sh syntax" bash -n "$H/precompact-save.sh"
expect "handoff-context.sh syntax" bash -n "$H/handoff-context.sh"
expect "handoff skill has name" has "$ROOT/skills/mogger-handoff/SKILL.md" "name: mogger-handoff"
expect "handoff skill demands UNVERIFIED label" has "$ROOT/skills/mogger-handoff/SKILL.md" "UNVERIFIED:"
expect "HANDOFF template has sections" bash -c "grep -q '## Next steps' '$ROOT/templates/HANDOFF.md' && grep -q '## Gotchas' '$ROOT/templates/HANDOFF.md' && grep -q '## How to run and test' '$ROOT/templates/HANDOFF.md'"

echo "== deploy.sh"
dp() { bash "$DEP" 2>/dev/null; }
lvl() { dp | grep "|$1|" | cut -d'|' -f1; }  # lvl <check-id>
rm -rf "$BASE/d"; mkdir -p "$BASE/d"; cd "$BASE/d"
OUT=$(dp); RC=$?
expect "empty dir: exit 0" eq "$RC" 0
expect "no git: FAIL deploy-git" eq "$(lvl deploy-git)" FAIL
expect "no .gitignore: WARN" eq "$(lvl deploy-gitignore)" WARN
expect "no CI: WARN" eq "$(lvl deploy-ci)" WARN
expect "no CI: tests check SKIP" eq "$(lvl deploy-ci-tests)" SKIP
expect "no rollback mention: WARN" eq "$(lvl deploy-rollback)" WARN
expect "no backup mention: WARN" eq "$(lvl deploy-backup)" WARN
expect "no staging: WARN" eq "$(lvl deploy-staging)" WARN
expect "no manifest: lockfile SKIP" eq "$(lvl deploy-lockfile)" SKIP
expect "every line has 3 fields and a valid level" bash -c "printf '%s\n' \"\$1\" | awk -F'|' 'NF<3 || \$1!~/^(PASS|WARN|FAIL|SKIP)\$/{exit 1}'" _ "$OUT"
git init -q .
expect "git without remote: WARN" eq "$(lvl deploy-git)" WARN
git remote add origin https://example.invalid/x.git
expect "git with remote: PASS" eq "$(lvl deploy-git)" PASS
printf '{"name":"x","scripts":{"start":"node a.js","build":"x","test":"jest"},"dependencies":{"express":"4"}}\n' > package.json
printf 'node_modules\n' > .gitignore
expect ".gitignore missing .env: WARN" eq "$(lvl deploy-gitignore)" WARN
printf 'node_modules\n.env\ndist\n' > .gitignore
expect ".gitignore complete: PASS" eq "$(lvl deploy-gitignore)" PASS
expect "package.json without lockfile: WARN" eq "$(lvl deploy-lockfile)" WARN
printf '{}' > package-lock.json
expect "lockfile untracked: WARN" eq "$(lvl deploy-lockfile)" WARN
git add package-lock.json
expect "lockfile committed/staged: PASS" eq "$(lvl deploy-lockfile)" PASS
expect "start script: PASS" eq "$(lvl deploy-runcmd)" PASS
expect "server without health: WARN" eq "$(lvl deploy-health)" WARN
printf 'app.get("/healthz", ok)\n' > server.js
expect "health route in code: PASS" eq "$(lvl deploy-health)" PASS
mkdir -p .github/workflows
printf 'on: push\njobs:\n  b:\n    steps:\n      - run: echo hi\n' > .github/workflows/ci.yml
expect "CI without tests: WARN" eq "$(lvl deploy-ci-tests)" WARN
printf 'on: push\njobs:\n  b:\n    steps:\n      - run: npm test\n      - run: deploy now\n' > .github/workflows/ci.yml
expect "CI present: PASS" eq "$(lvl deploy-ci)" PASS
expect "CI runs npm test: PASS" eq "$(lvl deploy-ci-tests)" PASS
expect "CI deploy step: flow PASS" eq "$(lvl deploy-flow)" PASS
printf '# App\nDeploy with scp -r dist user@host:/var/www\n' > README.md
expect "scp to server: flow WARN" eq "$(lvl deploy-flow)" WARN
printf '# App\nStaging site: staging.example.com. To roll back, redeploy the previous version. Nightly backup via pg_dump.\n' > README.md
expect "staging mentioned: PASS" eq "$(lvl deploy-staging)" PASS
expect "rollback mentioned: PASS" eq "$(lvl deploy-rollback)" PASS
expect "backup mentioned: PASS" eq "$(lvl deploy-backup)" PASS
mkdir -p migrations; : > migrations/001.sql
expect "migrations not in deploy path: WARN" eq "$(lvl deploy-migrations)" WARN
printf '{"scripts":{"start":"node a.js","release":"prisma migrate deploy"},"dependencies":{"express":"4"}}\n' > package.json
expect "migrate in package.json: PASS" eq "$(lvl deploy-migrations)" PASS
printf 'FROM node\n' > Dockerfile
expect "Dockerfile without CMD: WARN" eq "$(lvl deploy-runcmd)" WARN
printf 'FROM node\nCMD ["node","a.js"]\n' > Dockerfile
expect "Dockerfile with CMD: PASS" eq "$(lvl deploy-runcmd)" PASS
BEFORE=$(git status --porcelain | md5sum 2>/dev/null || git status --porcelain | md5)
dp >/dev/null
AFTER=$(git status --porcelain | md5sum 2>/dev/null || git status --porcelain | md5)
expect "deploy.sh leaves the project untouched" eq "$BEFORE" "$AFTER"
expect "deploy.sh syntax" bash -n "$DEP"

echo "== ship-check.sh: module aggregation"
rm -rf "$BASE/s"; mkdir -p "$BASE/s/checks"; cd "$BASE/s"
git init -q .; printf 'x\n' > README.md
mk() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$BASE/s/checks/$1.sh"; chmod +x "$BASE/s/checks/$1.sh"; }
mk alpha 'echo "PASS|alpha-one|all good"; echo "WARN|alpha-two|something odd | with a pipe"; exit 0'
mk beta 'echo "SKIP|beta-one|not applicable here"; exit 0'
export MOGGER_CHECKS_DIR="$BASE/s/checks"
ship() { bash "$SHIP" "$@" 2>&1; }
O=$(ship); RC=$?
printf '%s\n' "$O" > "$BASE/o1.txt"
expect "exit 0 by default" eq "$RC" 0
expect "module header printed" has "$BASE/o1.txt" "module: alpha"
expect "PASS line in style" bash -c "grep -Eq '^PASS +alpha-one +all good' '$BASE/o1.txt'"
expect "WARN line keeps pipe in message" bash -c "grep -Eq '^WARN +alpha-two +something odd \| with a pipe' '$BASE/o1.txt'"
expect "SKIP line printed" bash -c "grep -Eq '^SKIP +beta-one +not applicable' '$BASE/o1.txt'"
expect "built-in checks still run" has "$BASE/o1.txt" "readme"
expect "never pushes statement kept" has "$BASE/o1.txt" "nothing was pushed or deployed"
expect "header says never pushes or deploys" has "$BASE/o1.txt" "never pushes or deploys"
BI=$(bash -c "cd '$BASE/s'; MOGGER_CHECKS_DIR=/nonexistent bash '$SHIP' 2>&1" | grep '^-- ' | tail -1)
TOT=$(printf '%s\n' "$O" | grep '^-- .* pass' | tail -1)
P0=$(printf '%s' "$BI" | sed 's/^-- \([0-9]*\) pass.*/\1/'); P1=$(printf '%s' "$TOT" | sed 's/^-- \([0-9]*\) pass.*/\1/')
expect "module PASS counted in totals" eq "$P1" "$((P0 + 1))"
S0=$(printf '%s' "$BI" | sed 's/.* \([0-9]*\) skip.*/\1/'); S1=$(printf '%s' "$TOT" | sed 's/.* \([0-9]*\) skip.*/\1/')
expect "module SKIP counted in totals" eq "$S1" "$((S0 + 1 - 1))"
# --list
L=$(ship --list)
expect "--list shows alpha" bash -c "printf '%s\n' '$L' | grep -qx alpha"
expect "--list shows beta" bash -c "printf '%s\n' '$L' | grep -qx beta"
expect "--list prints no check lines" bash -c "! printf '%s\n' '$L' | grep -q 'PASS'"
# --only
O=$(ship --only alpha)
expect "--only runs the module" bash -c "printf '%s\n' '$O' | grep -q alpha-one"
expect "--only skips other modules" bash -c "! printf '%s\n' '$O' | grep -q beta-one"
expect "--only skips built-in checks" bash -c "! printf '%s\n' '$O' | grep -q 'readme'"
O=$(ship --only nosuch); RC=$?
expect "--only unknown module: SKIP" bash -c "printf '%s\n' '$O' | grep -Eq '^SKIP +nosuch +no such module'"
expect "--only unknown module: exit 0" eq "$RC" 0
# --strict
ship --strict >/dev/null; RC=$?
expect "--strict without FAIL from module: builtin decides" test "$RC" -le 1
mk gamma 'echo "FAIL|gamma-bad|broke it"; exit 0'
O=$(ship); RC=$?
expect "module FAIL shown" bash -c "printf '%s\n' '$O' | grep -Eq '^FAIL +gamma-bad +broke it'"
expect "FAIL without --strict: exit 0" eq "$RC" 0
ship --strict >/dev/null; RC=$?
expect "--strict with module FAIL: exit 1" eq "$RC" 1
ship --only alpha --strict >/dev/null; RC=$?
expect "--only alpha --strict: exit 0 (no FAIL in alpha)" eq "$RC" 0
ship --only gamma --strict >/dev/null; RC=$?
expect "--only gamma --strict: exit 1" eq "$RC" 1
rm -f checks/gamma.sh
# crashing / erroring modules
mk crash 'echo "PASS|crash-early|got this far"; exit 3'
mk boom 'echo oops >&2; kill -SEGV $$'
mk empty 'exit 0'
mk garbage 'echo "this is not a finding"; echo "PASS|only-two"; echo "BAD|x|y"; echo "PASS|good-one|fine"'
O=$(ship); RC=$?
printf '%s\n' "$O" > "$BASE/o2.txt"
expect "crashing modules: ship-check exits 0" eq "$RC" 0
expect "erroring module: partial findings kept" has "$BASE/o2.txt" "crash-early"
expect "erroring module: SKIP with reason" bash -c "grep -Eq '^SKIP +crash +module exited with status 3' '$BASE/o2.txt'"
expect "segfault module: SKIP with reason" bash -c "grep -Eq '^SKIP +boom +module exited' '$BASE/o2.txt'"
expect "module with no output: SKIP" bash -c "grep -Eq '^SKIP +empty +module produced no findings' '$BASE/o2.txt'"
expect "malformed line: WARN naming module" has "$BASE/o2.txt" "malformed line from garbage: this is not a finding"
expect "two-field line is malformed" has "$BASE/o2.txt" "malformed line from garbage: PASS|only-two"
expect "unknown level is malformed" has "$BASE/o2.txt" "malformed line from garbage: BAD|x|y"
expect "good line after garbage still shown" bash -c "grep -Eq '^PASS +good-one +fine' '$BASE/o2.txt'"
expect "later modules still run after crash" has "$BASE/o2.txt" "beta-one"
expect "totals line still printed" has "$BASE/o2.txt" "Push/deploy is a human decision"
rm -f checks/crash.sh checks/boom.sh checks/empty.sh checks/garbage.sh
mk noexec 'echo "PASS|x|y"'; chmod -x checks/noexec.sh
O=$(ship)
expect "non-executable module: SKIP with reason" bash -c "printf '%s\n' '$O' | grep -Eq '^SKIP +noexec +module not executable'"
expect "non-executable module is not run" bash -c "! printf '%s\n' '$O' | grep -Eq '^PASS +x '"
rm -f checks/noexec.sh
# timeout
mk slow 'sleep 20; echo "PASS|slow-one|done"'
if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
  S=$(date +%s); O=$(MOGGER_CHECK_TIMEOUT=1 ship); E=$(date +%s)
  expect "slow module is cut off" test $((E - S)) -lt 15
  expect "timeout reported as SKIP" bash -c "printf '%s\n' '$O' | grep -Eq '^SKIP +slow +timed out after 1s'"
  expect "other modules unaffected by timeout" bash -c "printf '%s\n' '$O' | grep -q alpha-one"
else
  ok "no timeout binary here; timeout tests skipped"
fi
rm -f checks/slow.sh
# no timeout binary on PATH: modules still run unbounded
mk fast 'echo "PASS|fast-one|ok"'
SAFE="$BASE/nobin"; mkdir -p "$SAFE"
for c in bash git grep sed awk cut tr sort head tail cat ls find xargs date sleep wc dirname basename mktemp rm mkdir touch stat uname printf env python3 jq; do
  P=$(command -v $c 2>/dev/null); [ -n "$P" ] && [ -x "$P" ] && ln -sf "$P" "$SAFE/$c"
done
O=$(PATH="$SAFE" bash "$SHIP" 2>&1); RC=$?
expect "no timeout/gtimeout on PATH: exit 0" eq "$RC" 0
expect "no timeout/gtimeout on PATH: module still runs" bash -c "printf '%s\n' '$O' | grep -Eq '^PASS +fast-one'"
rm -f checks/fast.sh
# missing checks dir
O=$(MOGGER_CHECKS_DIR="$BASE/none" bash "$SHIP" 2>&1); RC=$?
expect "missing checks dir: exit 0" eq "$RC" 0
expect "missing checks dir: SKIP with reason" bash -c "printf '%s\n' '$O' | grep -Eq '^SKIP +modules +no check modules found'"
unset MOGGER_CHECKS_DIR
# layout discovery next to the script (manual install)
rm -rf "$BASE/inst"; mkdir -p "$BASE/inst/checks" "$BASE/inst/hooks/scripts"
cp "$SHIP" "$BASE/inst/ship-check.sh"
printf '#!/usr/bin/env bash\necho "PASS|inst-one|found next to script"\n' > "$BASE/inst/checks/inst.sh"; chmod +x "$BASE/inst/checks/inst.sh"
O=$(cd "$BASE/s" && bash "$BASE/inst/ship-check.sh" 2>&1)
expect "checks/ next to ship-check.sh is discovered" bash -c "printf '%s\n' '$O' | grep -Eq '^PASS +inst-one'"
rm -rf "$BASE/inst2"; mkdir -p "$BASE/inst2/scripts/checks"
cp "$SHIP" "$BASE/inst2/scripts/ship-check.sh"
printf '#!/usr/bin/env bash\necho "PASS|inst2-one|repo layout"\n' > "$BASE/inst2/scripts/checks/inst2.sh"; chmod +x "$BASE/inst2/scripts/checks/inst2.sh"
O=$(cd "$BASE/s" && bash "$BASE/inst2/scripts/ship-check.sh" 2>&1)
expect "scripts/checks/ layout is discovered" bash -c "printf '%s\n' '$O' | grep -Eq '^PASS +inst2-one'"
expect "ship-check.sh syntax" bash -n "$SHIP"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
