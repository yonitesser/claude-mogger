#!/usr/bin/env bash
# Approval gate: known bypasses must block, prose that only mentions a command
# must pass. Run: bash tests/approval-bypass.test.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
H="$ROOT/hooks/scripts"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
SB=$(mktemp -d); trap 'rm -rf "$SB"' EXIT; cd "$SB"
git init -q -b feat .; git config user.email t@t; git config user.name t
export CLAUDE_PROJECT_DIR="$SB"; unset MOGGER_ALLOW_PUSH

PUSH="git"" push"   # built in two pieces so this file never trips a text match
bash_rc() {  # command -> exit code of require-approval.sh
  python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$1" \
    | bash "$H/require-approval.sh" >/dev/null 2>&1; echo $?
}
expect() {  # want cmd label
  local got; got=$(bash_rc "$2")
  [ "$got" = "$1" ] && ok "$3" || bad "$3 (want $1, got $got): $2"
}

echo "== bypasses that must be blocked"
expect 2 "$PUSH origin main"                                   "plain push"
expect 2 "bash -c \"$PUSH origin feat\""                       "bash -c wrapper"
expect 2 "sh -lc 'cd x && $PUSH'"                              "sh -lc wrapper"
expect 2 "eval \"$PUSH\""                                      "eval wrapper"
expect 2 "git -C . push"                                       "git -C"
expect 2 "git -c user.name=x push"                             "git -c"
expect 2 "git --git-dir=.git push"                             "git --git-dir"
expect 2 "sudo -u bob env A=1 $PUSH"                           "sudo/env prefix"
expect 2 "echo ok && \$($PUSH)"                                "command substitution"
expect 2 "echo \"\$($PUSH)\""                                  "substitution inside double quotes"
expect 2 "ls | xargs -n1 $PUSH"                                "xargs"
expect 2 "/usr/bin/git push"                                   "absolute git path"
expect 2 "wrangler deploy"                                     "wrangler deploy"
expect 2 "npx wrangler publish"                                "npx wrangler publish"
expect 2 "prisma migrate deploy"                               "prisma migrate deploy"
expect 2 "npx prisma db push"                                  "prisma db push"
expect 2 "supabase db push"                                    "supabase db push"
expect 2 "gh release create v1"                                "gh release create"
expect 2 "gh repo delete me/x --yes"                           "gh repo delete"
expect 2 "gh pr merge 5"                                       "gh pr merge"
expect 2 "bash -c \"gh pr merge 5\""                           "gh pr merge in bash -c"
expect 2 "echo 'unclosed ; $PUSH"                              "unparsable quote falls back to raw"

echo "== prose that only mentions a command must pass"
expect 0 "git commit -m \"docs: explain how to run $PUSH and npm publish\"" "commit message"
expect 0 "echo \"remember to run wrangler deploy later\""      "echo text"
expect 0 "grep -rn 'prisma migrate deploy' README.md"          "grep for a command"
expect 0 "cat <<'EOF' > notes.md
$PUSH origin main
supabase db push
EOF"                                                           "heredoc body"
expect 0 "git status"                                          "git status"
expect 0 "git -C . log --oneline"                              "git -C log"
expect 0 "npm test"                                            "npm test"
echo "== global options between tool and verb"
expect 2 "gh -R o/r pr merge 1"                                "gh -R pr merge"
expect 2 "gh api -X PUT repos/o/r/pulls/1/merge"               "gh api merge endpoint"
expect 2 "kubectl -n prod apply -f x.yaml"                     "kubectl -n apply"
expect 2 "terraform -chdir=infra apply"                        "terraform -chdir apply"
expect 2 "npm -w pkg publish"                                  "npm -w publish"
expect 2 "docker --context prod push img"                      "docker --context push"
expect 0 "kubectl -n prod get pods"                            "kubectl get is fine"
expect 0 "docker --context prod ps"                            "docker ps is fine"
expect 0 "gh -R o/r pr view 1"                                 "gh pr view is fine"
expect 0 "npm -w pkg test && echo publish"                    "word after && is not an npm verb"

echo "== allow-push mode still holds the line"
export MOGGER_ALLOW_PUSH=on
expect 0 "$PUSH origin feat"                                   "feature push allowed when opted in"
expect 2 "bash -c \"$PUSH --force origin feat\""               "force inside bash -c"
expect 2 "git -C . push origin main"                           "protected branch via git -C"
expect 2 "$PUSH origin +feat"                                  "plus-refspec"
expect 2 "$PUSH -uf origin feat"                               "combined short flags -uf"
expect 2 "$PUSH --forc origin feat"                            "abbreviated --forc"
expect 2 "$PUSH --del origin feat"                             "abbreviated --del"
expect 0 "$PUSH -u origin feat"                                "-u alone is fine"
expect 0 "$PUSH --follow-tags origin feat"                     "--follow-tags is not a force"
unset MOGGER_ALLOW_PUSH

echo "== GitHub MCP tools"
mcp_rc() {  # tool json
  printf '{"tool_name":"%s","tool_input":%s}' "$1" "${2:-{\}}" | bash "$H/require-approval-mcp.sh" >/dev/null 2>&1; echo $?
}
mexpect() { local got; got=$(MOGGER_ALLOW_PUSH="${4:-}" mcp_rc "$2" "$3"); [ "$got" = "$1" ] && ok "$5" || bad "$5 (want $1, got $got)"; }
mexpect 2 mcp__github__merge_pull_request '{"pullNumber":1}' ""    "merge_pull_request blocked"
mexpect 2 mcp__github__merge_pull_request '{"pullNumber":1}' on    "merge_pull_request blocked even when push allowed"
mexpect 2 mcp__github__enable_pr_auto_merge '{}' on               "auto-merge blocked"
mexpect 2 mcp__github__push_files '{"branch":"feat"}' ""          "push_files blocked by default"
mexpect 0 mcp__github__push_files '{"branch":"feat"}' on          "push_files to a feature branch ok when opted in"
mexpect 2 mcp__github__push_files '{"branch":"main"}' on          "push_files to main blocked"
mexpect 2 mcp__github__create_or_update_file '{}' on              "no branch named -> blocked"
mexpect 0 mcp__github__create_pull_request '{"head":"feat"}' ""   "create_pull_request not gated"
mexpect 0 mcp__github__get_file_contents '{}' ""                  "reads not gated"

echo "== normaliser always exits 0 and never hangs"
TMO=""; command -v timeout >/dev/null 2>&1 && TMO="timeout 5"   # macOS has no timeout(1)
for in in '' '"' "'" '$(' '`' '\' 'a;;b' '(((' "$(printf 'x%.0s' $(seq 1 5000))"; do
  printf '%s' "$in" | ${TMO:-} python3 "$H/cmd-normalize.py" >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] && ok "normaliser ok on '${in:0:12}'" || bad "normaliser rc=$rc on '${in:0:12}'"
done
echo "approval-bypass: $PASS passed, $FAIL failed"; [ "$FAIL" = 0 ]
