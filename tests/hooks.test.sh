#!/usr/bin/env bash
# Tests for the hooks. Run: bash tests/hooks.test.sh
# Each case feeds a hook the JSON Claude Code would send it and asserts
# the exit code. 0 = allow, 2 = block. If this file doesn't pass, the
# gates don't work, and nothing else in this kit matters.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
H="$ROOT/hooks/scripts"
PASS=0; FAIL=0

# Sandbox: a throwaway git repo so branch checks and file mtimes are real
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
cd "$SANDBOX"
git init -q -b main . 2>/dev/null || { git init -q .; git checkout -q -b main; }
git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init

expect() {  # expect <exit_code> <hook> <json> <description>
  local want="$1" hook="$2" json="$3" desc="$4" got
  printf '%s' "$json" | bash "$H/$hook" >/dev/null 2>&1; got=$?
  if [ "$got" -eq "$want" ]; then PASS=$((PASS+1)); printf '  ok   %-28s %s\n' "$hook" "$desc"
  else FAIL=$((FAIL+1)); printf '  FAIL %-28s %s (want %s, got %s)\n' "$hook" "$desc" "$want" "$got"; fi
}
bash_cmd() {  # builds {"tool_name":"Bash","tool_input":{"command":"..."}} without requiring python3
  local raw="$1" esc
  if command -v jq >/dev/null 2>&1; then
    esc=$(printf '%s' "$raw" | jq -Rs .)
  elif command -v python3 >/dev/null 2>&1 && python3 -c '1' >/dev/null 2>&1; then
    # only trust python3 if it can actually execute, not a Windows Store stub
    esc=$(printf '%s' "$raw" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')
  else
    # pure-bash fallback: escape backslash and double-quote, good enough for test commands
    local body="${raw//\\/\\\\}"
    body="${body//\"/\\\"}"
    esc="\"$body\""
  fi
  printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$esc"
}
file_json() { printf '{"tool_name":"%s","tool_input":{"file_path":"%s"}}' "$1" "$2"; }
task_json() { printf '{"tool_name":"Task","tool_input":{"subagent_type":"%s"}}' "$1"; }

echo "== require-approval.sh"
expect 2 require-approval.sh "$(bash_cmd 'git push origin main')"              "blocks git push"
expect 2 require-approval.sh "$(bash_cmd 'git push --force')"                  "blocks force push"
expect 2 require-approval.sh "$(bash_cmd 'cd app && git push')"                "blocks push after cd"
expect 2 require-approval.sh "$(bash_cmd 'gh pr merge 42')"                    "blocks gh pr merge"
expect 2 require-approval.sh "$(bash_cmd 'git merge feature/x')"               "blocks merge while ON main"
git checkout -q -b feature/test
expect 0 require-approval.sh "$(bash_cmd 'git merge main')"                    "allows merging main INTO feature branch"
git checkout -q main
expect 2 require-approval.sh "$(bash_cmd 'npm publish')"                       "blocks npm publish"
expect 2 require-approval.sh "$(bash_cmd 'terraform apply -auto-approve')"     "blocks terraform apply"
expect 2 require-approval.sh "$(bash_cmd 'kubectl apply -f k8s/')"             "blocks kubectl apply"
expect 2 require-approval.sh "$(bash_cmd 'vercel deploy --prod')"              "blocks vercel --prod"
expect 0 require-approval.sh "$(bash_cmd 'vercel deploy')"                     "allows vercel preview deploy"
expect 2 require-approval.sh "$(bash_cmd 'stripe charges create --amount 100')" "blocks stripe charge"
expect 2 require-approval.sh "$(bash_cmd 'aws ce get-cost-and-usage')"         "blocks aws cost explorer"
expect 0 require-approval.sh "$(bash_cmd 'cat payment_service.py')"            "ALLOWS reading a file named payment (false-positive fix)"
expect 0 require-approval.sh "$(bash_cmd 'grep -r invoice src/')"              "ALLOWS grepping for 'invoice'"
expect 0 require-approval.sh "$(bash_cmd 'git status')"                        "allows git status"
expect 0 require-approval.sh "$(bash_cmd 'git commit -m x')"                   "allows git commit"
expect 0 require-approval.sh "$(bash_cmd 'npm test')"                          "allows npm test"

echo "== protect-pipeline-files.sh"
expect 2 protect-pipeline-files.sh "$(file_json Edit .github/workflows/ci.yml)"    "blocks CI workflow edit"
expect 2 protect-pipeline-files.sh "$(file_json Write Dockerfile)"               "blocks Dockerfile"
expect 2 protect-pipeline-files.sh "$(file_json Edit infra/main.tf)"             "blocks terraform"
expect 2 protect-pipeline-files.sh "$(file_json Edit src/billing/stripe.ts)"     "blocks payment code"
expect 0 protect-pipeline-files.sh "$(file_json Edit src/utils/date.ts)"         "allows normal source file"

echo "== check-file-size.sh"
seq 1 400 > big.txt; seq 1 10 > small.txt
expect 2 check-file-size.sh "$(file_json Read "$SANDBOX/big.txt")"               "blocks 400-line file"
expect 0 check-file-size.sh "$(file_json Read "$SANDBOX/small.txt")"             "allows 10-line file"
expect 0 check-file-size.sh "$(file_json Read "$SANDBOX/does-not-exist.txt")"    "allows missing file (fails open)"

echo "== check-bash-read.sh"
expect 2 check-bash-read.sh "$(bash_cmd "cat $SANDBOX/big.txt")"                "blocks cat on big file"
expect 0 check-bash-read.sh "$(bash_cmd "cat $SANDBOX/small.txt")"              "allows cat on small file"
expect 0 check-bash-read.sh "$(bash_cmd "ls -la")"                              "ignores non-read commands"

echo "== require-tests-pass.sh"
mkdir -p .claude/state
rm -f .claude/state/last_test_result.json
expect 2 require-tests-pass.sh "$(task_json reviewer)"                          "blocks reviewer with no test marker"
expect 0 require-tests-pass.sh "$(task_json builder)"                           "ignores non-reviewer agents"
echo '{"status":"fail","exit_code":1}' > .claude/state/last_test_result.json
expect 2 require-tests-pass.sh "$(task_json reviewer)"                          "blocks reviewer on recorded fail"
echo '{"status":"pass","exit_code":0}' > .claude/state/last_test_result.json
sleep 1; touch -d '2000-01-01' small.txt big.txt 2>/dev/null || true
expect 0 require-tests-pass.sh "$(task_json reviewer)"                          "allows reviewer on fresh pass"
sleep 1; echo x >> small.txt
expect 2 require-tests-pass.sh "$(task_json reviewer)"                          "blocks reviewer when a file changed after pass (stale)"

echo "== stop-done-means-done.sh"
rm -f TASKS.md
expect 0 stop-done-means-done.sh '{}'                                            "allows stop with no TASKS.md"
printf '# TASKS\n\n## Status: in-progress\n\n- [x] 1. done\n- [ ] 2. open\n' > TASKS.md
expect 2 stop-done-means-done.sh '{}'                                            "blocks stop with open task, no blocker"
expect 0 stop-done-means-done.sh '{"stop_hook_active":true}'                    "allows stop when hook already fired (no loop)"
printf '# TASKS\n\n## Status: in-progress\n\n- [ ] 2. open\nBLOCKED: needs API key from user\n' > TASKS.md
expect 0 stop-done-means-done.sh '{}'                                            "allows stop with BLOCKED: line"
printf '# TASKS\n\n## Status: awaiting-approval\n\n- [ ] 2. merge\n' > TASKS.md
expect 0 stop-done-means-done.sh '{}'                                            "allows stop when awaiting-approval"
printf '# TASKS\n\n- [x] 1. done\n- [x] 2. done\n' > TASKS.md
expect 0 stop-done-means-done.sh '{}'                                            "allows stop when all tasks done"

echo "== session-start.sh (count correctness)"
printf '# T\n\n- [x] 1. done\n- [ ] 2. open\n- [ ] 3. open\n' > TASKS.md
OUT=$(bash "$H/session-start.sh" 2>/dev/null)
if echo "$OUT" | grep -q "1 done, 2 open"; then PASS=$((PASS+1)); echo "  ok   session-start.sh             counts tasks correctly (1 done, 2 open)"
else FAIL=$((FAIL+1)); echo "  FAIL session-start.sh             wrong task count: $(echo "$OUT" | grep 'TASKS.md status')"; fi
rm -f TASKS.md

echo "== session-start.sh"
printf '# CONSTRAINTS.md\n\n## Corrections\n\n- 2026-09-01: used wrong http lib → check STACK.md first\n' > CONSTRAINTS.md
OUT=$(bash "$H/session-start.sh" 2>/dev/null)
if echo "$OUT" | grep -q "wrong http lib"; then PASS=$((PASS+1)); echo "  ok   session-start.sh             injects CONSTRAINTS.md content"
else FAIL=$((FAIL+1)); echo "  FAIL session-start.sh             did not inject CONSTRAINTS.md"; fi

echo "== auto-format.sh"
expect 0 auto-format.sh "$(file_json Edit "$SANDBOX/small.txt")"                "never blocks (exit 0 even with no formatter)"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
