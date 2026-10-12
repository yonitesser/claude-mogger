#!/usr/bin/env bash
# The third guard state: "ask" (permission prompt each time) next to on and off.
# Run: bash tests/ask.test.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
H="$ROOT/hooks/scripts"; C="$ROOT/scripts/mogger-config.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
SB=$(mktemp -d); trap 'rm -rf "$SB"' EXIT
export CLAUDE_PROJECT_DIR="$SB"
cd "$SB" && git init -q -b work . 2>/dev/null; git -C "$SB" commit -q --allow-empty -m x 2>/dev/null
unset MOGGER_DANGER_GUARD MOGGER_SECRET_READ MOGGER_CONFIG_GUARD MOGGER_PUSH_GUARD MOGGER_MERGE_GUARD \
      MOGGER_DEPLOY_GUARD MOGGER_MONEY_GUARD MOGGER_ALLOW_PUSH MOGGER_HEADLESS CLAUDE_CODE_ENTRYPOINT

bash_in() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1"; }
bash_pm() { printf '{"tool_name":"Bash","permission_mode":"%s","tool_input":{"command":"%s"}}' "$1" "$2"; }
# run <hook> <json> -> sets RC, OUT (stdout) and ERR (stderr)
run() { OUT=$(printf '%s' "$2" | bash "$H/$1" 2>"$SB/err"); RC=$?; ERR=$(cat "$SB/err"); }
is_ask() { printf '%s' "$OUT" | jq -e '.hookSpecificOutput.permissionDecision=="ask" and (.hookSpecificOutput.permissionDecisionReason|length>0)' >/dev/null 2>&1; }
# the risky command, built from parts so this file is not itself a risky command line
RESET="git re""set --hard"

DANGER=$(bash_in "$RESET")
# --- danger-guard: on / ask / off / bad value / env / file
run danger-guard.sh "$DANGER"; [ $RC -eq 2 ] && ok "danger on: blocks (exit 2)" || bad "danger on"
MOGGER_DANGER_GUARD=ask run danger-guard.sh "$DANGER"; [ $RC -eq 0 ] && is_ask && ok "danger ask: returns the ask decision" || bad "danger ask rc=$RC out=$OUT"
MOGGER_DANGER_GUARD=off run danger-guard.sh "$DANGER"; [ $RC -eq 0 ] && [ -z "$OUT" ] && ok "danger off: allows, no output" || bad "danger off"
MOGGER_DANGER_GUARD=maybe run danger-guard.sh "$DANGER"; [ $RC -eq 2 ] && ok "danger bad env value: fails safe to block" || bad "danger bad value"
MOGGER_DANGER_GUARD=ask run danger-guard.sh "$(bash_in 'ls -la')"; [ $RC -eq 0 ] && [ -z "$OUT" ] && ok "danger ask: harmless command passes untouched" || bad "danger ask harmless"

# file value, env wins over file
bash "$C" set danger-guard ask >/dev/null; run danger-guard.sh "$DANGER"; [ $RC -eq 0 ] && is_ask && ok "danger ask from .claude/mogger.json" || bad "danger ask file"
MOGGER_DANGER_GUARD=on run danger-guard.sh "$DANGER"; [ $RC -eq 2 ] && ok "env on wins over file ask" || bad "env over file"
MOGGER_DANGER_GUARD=off run danger-guard.sh "$DANGER"; [ $RC -eq 0 ] && [ -z "$OUT" ] && ok "env off wins over file ask" || bad "env off over file"
printf '{"danger-guard":"banana"}' > "$SB/.claude/mogger.json"; run danger-guard.sh "$DANGER"; [ $RC -eq 2 ] && ok "bad file value: guard keeps its default (block)" || bad "bad file value"
printf '{"danger-guard":"ask"' > "$SB/.claude/mogger.json"; run danger-guard.sh "$DANGER"; [ $RC -eq 2 ] && ok "broken file: guard keeps its default (block)" || bad "broken file"
rm -f "$SB/.claude/mogger.json"

# --- no prompt available: ask must block, never allow
for mode in bypassPermissions dontAsk auto; do
  MOGGER_DANGER_GUARD=ask run danger-guard.sh "$(bash_pm $mode "$RESET")"
  [ $RC -eq 2 ] && [ -z "$OUT" ] && ok "ask in $mode mode: blocks" || bad "ask in $mode"
done
MOGGER_DANGER_GUARD=ask run danger-guard.sh "$(bash_pm default "$RESET")"; [ $RC -eq 0 ] && is_ask && ok "ask in default mode: prompts" || bad "ask default mode"
MOGGER_DANGER_GUARD=ask CLAUDE_CODE_ENTRYPOINT=sdk-cli run danger-guard.sh "$DANGER"; [ $RC -eq 2 ] && ok "ask in a headless/SDK run: blocks" || bad "ask headless"
MOGGER_DANGER_GUARD=ask MOGGER_HEADLESS=on run danger-guard.sh "$DANGER"; [ $RC -eq 2 ] && ok "MOGGER_HEADLESS=on: ask blocks" || bad "MOGGER_HEADLESS"

# --- secret-read-guard
SEC=$(bash_in 'cat .env')
run secret-read-guard.sh "$SEC"; [ $RC -eq 2 ] && ok "secret-read on: blocks" || bad "secret-read on"
MOGGER_SECRET_READ=ask run secret-read-guard.sh "$SEC"; [ $RC -eq 0 ] && is_ask && ok "secret-read ask: ask decision" || bad "secret-read ask"
MOGGER_SECRET_READ=ask run secret-read-guard.sh '{"tool_name":"Read","permission_mode":"bypassPermissions","tool_input":{"file_path":"/home/u/.ssh/id_rsa"}}'; [ $RC -eq 2 ] && ok "secret-read ask in bypass mode: blocks" || bad "secret-read bypass"
MOGGER_SECRET_READ=off run secret-read-guard.sh "$SEC"; [ $RC -eq 0 ] && [ -z "$OUT" ] && ok "secret-read off: allows" || bad "secret-read off"

# --- config-guard: ask by default, blocks when no prompt, off allows
CFGEDIT='{"tool_name":"Edit","tool_input":{"file_path":"/p/.claude/settings.json"}}'
run config-guard.sh "$CFGEDIT"; [ $RC -eq 0 ] && is_ask && ok "config-guard default: ask" || bad "config-guard default"
MOGGER_CONFIG_GUARD=ask run config-guard.sh "$CFGEDIT"; [ $RC -eq 0 ] && is_ask && ok "config-guard ask: ask" || bad "config-guard ask"
MOGGER_CONFIG_GUARD=off run config-guard.sh "$CFGEDIT"; [ $RC -eq 0 ] && [ -z "$OUT" ] && ok "config-guard off: allows" || bad "config-guard off"
MOGGER_CONFIG_GUARD=zzz run config-guard.sh "$CFGEDIT"; [ $RC -eq 0 ] && is_ask && ok "config-guard bad value: default (ask)" || bad "config-guard bad"
run config-guard.sh '{"tool_name":"Edit","permission_mode":"bypassPermissions","tool_input":{"file_path":"/p/.mcp.json"}}'; [ $RC -eq 2 ] && ok "config-guard in bypass mode: blocks, never allows" || bad "config-guard bypass"
run config-guard.sh '{"tool_name":"Write","tool_input":{"file_path":"/p/.claude/mogger.json"}}'; [ $RC -eq 0 ] && is_ask && ok "config-guard asks before an edit of .claude/mogger.json" || bad "mogger.json write"
run config-guard.sh "$(bash_in 'echo {} > .claude/mogger.json')"; [ $RC -eq 0 ] && is_ask && ok "config-guard asks before a shell write to mogger.json" || bad "mogger.json shell write"
run config-guard.sh "$(bash_in 'cat .claude/mogger.json')"; [ $RC -eq 0 ] && [ -z "$OUT" ] && ok "config-guard lets a read of mogger.json pass" || bad "mogger.json read"
run config-guard.sh '{"tool_name":"Write","permission_mode":"bypassPermissions","tool_input":{"file_path":"/p/.claude/mogger.json"}}'; [ $RC -eq 2 ] && ok "mogger.json write in bypass mode: blocks" || bad "mogger.json bypass"
run config-guard.sh '{"tool_name":"Write","tool_input":{"file_path":"/p/.claude/mogger.json.bak"}}'; [ $RC -eq 0 ] && [ -z "$OUT" ] && ok "look-alike file name passes" || bad "look-alike"
CLAUDE_CODE_ENTRYPOINT=sdk-ts run config-guard.sh "$CFGEDIT"; [ $RC -eq 2 ] && ok "config-guard headless: blocks" || bad "config-guard headless"

# --- push / merge / deploy / money (require-approval.sh)
PUSH=$(bash_in 'git push origin work'); FORCE=$(bash_in 'git push --force origin work'); PROT=$(bash_in 'git push origin main')
run require-approval.sh "$PUSH"; [ $RC -eq 2 ] && ok "push on: blocks" || bad "push on"
MOGGER_PUSH_GUARD=ask run require-approval.sh "$PUSH"; [ $RC -eq 0 ] && is_ask && ok "push ask: ask decision" || bad "push ask rc=$RC $OUT"
MOGGER_PUSH_GUARD=ask run require-approval.sh "$FORCE"; [ $RC -eq 2 ] && ok "push ask: force push still blocked" || bad "push ask force"
MOGGER_PUSH_GUARD=ask run require-approval.sh "$PROT"; [ $RC -eq 2 ] && ok "push ask: protected branch still blocked" || bad "push ask protected"
MOGGER_PUSH_GUARD=ask run require-approval.sh "$(bash_in 'git push origin work && git push --force origin work')"; [ $RC -eq 2 ] && ok "push ask: a force push later in the line still blocks" || bad "push ask chained"
MOGGER_PUSH_GUARD=off run require-approval.sh "$PUSH"; [ $RC -eq 0 ] && [ -z "$OUT" ] && ok "push off: plain push allowed" || bad "push off"
MOGGER_PUSH_GUARD=off run require-approval.sh "$FORCE"; [ $RC -eq 2 ] && ok "push off: force push still blocked" || bad "push off force"
MOGGER_ALLOW_PUSH=on run require-approval.sh "$PUSH"; [ $RC -eq 0 ] && [ -z "$OUT" ] && ok "MOGGER_ALLOW_PUSH=on still allows (old name)" || bad "ALLOW_PUSH"
MOGGER_ALLOW_PUSH=on MOGGER_PUSH_GUARD=ask run require-approval.sh "$PUSH"; [ $RC -eq 0 ] && is_ask && ok "ALLOW_PUSH=on does not weaken ask" || bad "ALLOW_PUSH vs ask"
MOGGER_PUSH_GUARD=ask run require-approval.sh "$(bash_pm bypassPermissions 'git push origin work')"; [ $RC -eq 2 ] && ok "push ask in bypass mode: blocks" || bad "push ask bypass"
MOGGER_PUSH_GUARD=banana run require-approval.sh "$PUSH"; [ $RC -eq 2 ] && ok "push bad value: blocks" || bad "push bad value"

MERGE=$(bash_in 'gh pr merge 5')
run require-approval.sh "$MERGE"; [ $RC -eq 2 ] && ok "merge on: blocks" || bad "merge on"
MOGGER_MERGE_GUARD=ask run require-approval.sh "$MERGE"; [ $RC -eq 0 ] && is_ask && ok "merge ask: ask decision" || bad "merge ask"
MOGGER_MERGE_GUARD=off run require-approval.sh "$MERGE"; [ $RC -eq 2 ] && ok "merge-guard has no off: stays blocked" || bad "merge off"

DEPLOY=$(bash_in 'npm publish')
run require-approval.sh "$DEPLOY"; [ $RC -eq 2 ] && ok "deploy on: blocks" || bad "deploy on"
MOGGER_DEPLOY_GUARD=ask run require-approval.sh "$DEPLOY"; [ $RC -eq 0 ] && is_ask && ok "deploy ask: ask decision" || bad "deploy ask"
MOGGER_DEPLOY_GUARD=off run require-approval.sh "$DEPLOY"; [ $RC -eq 0 ] && [ -z "$OUT" ] && ok "deploy off: allows" || bad "deploy off"
MOGGER_DEPLOY_GUARD=ask run require-approval.sh "$(bash_in 'npm publish && gh pr merge 5')"; [ $RC -eq 2 ] && ok "deploy ask + merge on in one line: blocks" || bad "mixed states"
MOGGER_DEPLOY_GUARD=ask CLAUDE_CODE_ENTRYPOINT=sdk-cli run require-approval.sh "$DEPLOY"; [ $RC -eq 2 ] && ok "deploy ask headless: blocks" || bad "deploy headless"

MONEY=$(bash_in 'stripe refunds create --charge ch_1')
run require-approval.sh "$MONEY"; [ $RC -eq 2 ] && ok "money on: blocks" || bad "money on"
MOGGER_MONEY_GUARD=ask run require-approval.sh "$MONEY"; [ $RC -eq 0 ] && is_ask && ok "money ask: ask decision" || bad "money ask"
MOGGER_MONEY_GUARD=off run require-approval.sh "$MONEY"; [ $RC -eq 0 ] && [ -z "$OUT" ] && ok "money off: allows" || bad "money off"
MOGGER_PUSH_GUARD=ask MOGGER_DEPLOY_GUARD=ask MOGGER_MONEY_GUARD=ask MOGGER_MERGE_GUARD=ask run require-approval.sh "$(bash_in 'git status')"; [ $RC -eq 0 ] && [ -z "$OUT" ] && ok "all ask: harmless command untouched" || bad "harmless"

# --- the same states on the GitHub MCP gate
MCPM='{"tool_name":"mcp__github__merge_pull_request","tool_input":{"pullNumber":1}}'
MCPP='{"tool_name":"mcp__github__push_files","tool_input":{"branch":"work"}}'
run require-approval-mcp.sh "$MCPM"; [ $RC -eq 2 ] && ok "mcp merge on: blocks" || bad "mcp merge"
MOGGER_MERGE_GUARD=ask run require-approval-mcp.sh "$MCPM"; [ $RC -eq 0 ] && is_ask && ok "mcp merge ask: ask decision" || bad "mcp merge ask"
MOGGER_PUSH_GUARD=ask run require-approval-mcp.sh "$MCPP"; [ $RC -eq 0 ] && is_ask && ok "mcp push_files ask: ask decision" || bad "mcp push ask"
MOGGER_PUSH_GUARD=ask run require-approval-mcp.sh '{"tool_name":"mcp__github__push_files","tool_input":{"branch":"main"}}'; [ $RC -eq 2 ] && ok "mcp push_files ask: protected branch blocked" || bad "mcp protected"
MOGGER_PUSH_GUARD=ask MOGGER_HEADLESS=on run require-approval-mcp.sh "$MCPP"; [ $RC -eq 2 ] && ok "mcp ask headless: blocks" || bad "mcp headless"

# --- mogger:config script
bash "$C" set push-guard ask >/dev/null 2>&1; [ $? -eq 0 ] && ok "set ... ask works, no --confirm needed" || bad "set ask"
jq -e '."push-guard"=="ask"' "$SB/.claude/mogger.json" >/dev/null && ok "ask saved to .claude/mogger.json" || bad "ask not saved"
run require-approval.sh "$PUSH"; [ $RC -eq 0 ] && is_ask && ok "file ask reaches the hook" || bad "file ask reach"
bash "$C" list | grep -q '^push-guard | ask (file) | safety | on,ask' && ok "list shows ask and allowed states" || bad "list ask"
bash "$C" set danger-guard off >/dev/null 2>&1; [ $? -eq 3 ] && ok "safety off still needs --confirm" || bad "off confirm"
bash "$C" set push-guard off --confirm >/dev/null 2>&1; [ $? -eq 1 ] && ok "push-guard off not offered by the script (env var only)" || bad "push off allowed"
bash "$C" set deploy-guard off --confirm >/dev/null 2>&1; [ $? -eq 1 ] && ok "deploy-guard off not offered by the script" || bad "deploy off allowed"
bash "$C" set money-guard off --confirm >/dev/null 2>&1; [ $? -eq 1 ] && ok "money-guard off not offered by the script" || bad "money off allowed"
printf '{"push-guard":"off","money-guard":"off"}' > "$SB/.claude/mogger.json"
run require-approval.sh "$PUSH"; [ $RC -eq 2 ] && ok "off written by hand into the file is ignored (still blocks)" || bad "hand-written off honoured"
bash "$C" set hint-noisy-bash ask >/dev/null 2>&1; [ $? -eq 1 ] && ok "ask refused for a guard that cannot ask" || bad "ask on non-ask guard"
bash "$C" set merge-guard off --confirm >/dev/null 2>&1; [ $? -eq 1 ] && ok "off refused for merge-guard" || bad "merge off allowed"
bash "$C" set danger-guard maybe >/dev/null 2>&1; [ $? -eq 1 ] && ok "bad value rejected" || bad "bad value accepted"
bash "$C" set config-guard on >/dev/null 2>&1; [ $? -eq 1 ] && ok "config-guard has no on (it already asks)" || bad "config-guard on"
MOGGER_PUSH_GUARD=on bash "$C" list | grep -q '^push-guard | on (env)' && ok "list shows env state" || bad "list env"
MOGGER_HINT=ask bash "$C" list | grep -q '^hint-noisy-bash | on (env)' && ok "env ask on a non-ask guard reads as on" || bad "list env non-ask"
bash "$C" reset all >/dev/null

# --- catalog sanity: nine columns, ask rows have text, default inside states
while IFS=$'\t' read -r n e kind onv dflt on_t off_t states ask_t extra; do
  [ -z "${extra:-}" ] && [ -n "$ask_t" ] || { bad "$n: catalog row needs exactly 9 columns"; continue; }
  case ",$states," in *,ask,*) [ "$ask_t" != "-" ] || bad "$n: can ask but has no ASK text" ;; esac
  case ",$states," in *",$dflt,"*) ;; *) bad "$n: default $dflt not in states" ;; esac
done < <(grep -v '^#' "$ROOT/hooks/guards.tsv")
ok "catalog rows: 9 columns, default inside states, ASK text present"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"; [ "$FAIL" -eq 0 ]
