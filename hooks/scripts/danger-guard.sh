#!/usr/bin/env bash
# PreToolUse hook — matches: Bash
# Blocks shell commands that can destroy data or the machine: recursive rm of
# root/home/system dirs, dd/mkfs on devices, curl|sh, chmod 777, git reset
# --hard / clean -f / checkout ., rm -rf .git, --no-verify, AI agents started with
# permission checks off, and destructive SQL (DROP, TRUNCATE, DELETE with no WHERE).
# Plain text matching, so it can be bypassed on purpose; it is a seat belt
# against mistakes, not a sandbox. Fails open on bad input.
# States (MOGGER_DANGER_GUARD): on = block (default), ask = permission prompt for
# the human, off = allow. Where no prompt can be shown, ask blocks.

source "${0%/*}/lib.sh"
STATE=$(mogger_state MOGGER_DANGER_GUARD on)
[ "$STATE" = "off" ] && exit 0

INPUT=$(cat)
CMD=$(json_get "$INPUT" '.tool_input.command')
[ -z "$CMD" ] && exit 0

block() {  # block <short event text> <what was found>
  if [ "$STATE" = ask ] && mogger_can_ask "$INPUT"; then
    mogger_event warn "asked before: $1"
    mogger_ask_json "Mogger: $2. This can destroy data or the machine. Approve only if you want it to run."
    exit 0
  fi
  mogger_event block "$1"
  echo "BLOCKED: $2. This can destroy data or the machine. Ask the human to run it, or to set MOGGER_DANGER_GUARD=off." >&2
  exit 2
}

# Quotes and backticks removed so wrappers like bash -c "rm -rf /" are seen.
# Pure bash from here on (no grep/sed/tr per check): this hook runs on every Bash call.
shopt -s nocasematch   # replaces lower-casing the text; `=~` and `case` both honour it
CLEAN=${CMD//[\"\'\`]/}
CLEAN=${CLEAN//\$\{HOME\}/\$HOME}
LC=${CLEAN//$'\n'/;}   # one line, so `$` and `^` in the patterns below mean end/start of the command

SEP='[;|&(){}]'   # in a variable: a literal } inside ${var//[..}]/..} ends the expansion early
# 1. rm -r on root, home, cwd, wildcards or system dirs
BAD='^(\.git/?|/|/\*|~|~/|~/\*|\$HOME|\$HOME/|\$HOME/\*|\.|\./|\.\.|\.\./|\*|\./\*|\.\./\*|/(etc|usr|var|bin|sbin|lib|lib64|boot|root|home|opt|dev|proc|sys|System|Library|Users|Applications)/?|/(etc|usr|var|bin|sbin|lib|boot|root|home|opt|Users)/\*|/(home|Users)/[^/]+/?|/(home|Users)/[^/]+/\*)$'
while IFS= read -r seg; do
  read -ra W <<<"$seg"
  in_rm=0; rec=0; targets=()
  for w in "${W[@]}"; do
    if [ "$in_rm" = 0 ]; then
      case "$w" in rm|*/rm) in_rm=1 ;; esac
      continue
    fi
    case "$w" in
      --recursive) rec=1 ;;
      --*) ;;
      -*) case "$w" in *r*|*R*) rec=1 ;; esac ;;
      *) targets+=("$w") ;;
    esac
  done
  if [ "$in_rm" = 1 ] && [ "$rec" = 1 ]; then
    for t in "${targets[@]}"; do
      [[ "$t" =~ $BAD ]] && block "blocked rm -r on $t" "rm -r on '$t'"
    done
  fi
done <<<"${CLEAN//$SEP/$'\n'}"

# 2. Disks and fork bombs
mogger_re "$LC" 'dd[[:space:]]+[^;&|]*of=/dev/' && block "blocked dd to a device" "dd writing to a device"
mogger_re "$LC" '(^|[[:space:];&|])mkfs(\.[a-z0-9]+)?([[:space:]]|$)' && block "blocked mkfs" "mkfs formats a disk"
mogger_re "$LC" '>[[:space:]]*/dev/(sd|nvme|hd|disk|vd)' && block "blocked write to a disk device" "redirect into a disk device"
mogger_re "$CMD" ':\(\)[[:space:]]*\{' && block "blocked fork bomb" "fork bomb"

# 3. Download piped into a shell
mogger_re "$LC" '(curl|wget)[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(env[[:space:]]+)?(ba|z|da|k|fi)?sh([[:space:]]|$)' && block "blocked curl piped to shell" "download piped into a shell"
mogger_re "$LC" '((ba|z|da|k)?sh|eval)[[:space:]]+(-c[[:space:]]+)?(<\(|\$\()[[:space:]]*(curl|wget)' && block "blocked curl run as shell code" "downloaded script run as code"

# 4. World-writable permissions
mogger_re "$LC" 'chmod[[:space:]]+(-[a-z]+[[:space:]]+)*(0?777|a\+rwx|ugo\+rwx)([[:space:]]|$)' && block "blocked chmod 777" "chmod 777 (anyone can write)"

# 5. Git commands that throw away uncommitted work
mogger_re "$LC" 'git[[:space:]]+([^;&|]*[[:space:]])?reset[[:space:]]+([^;&|]*[[:space:]])?--hard' && block "blocked git reset --hard" "git reset --hard (drops uncommitted work)"
if mogger_re "$LC" 'git[[:space:]]+([^;&|]*[[:space:]])?clean[[:space:]]+[^;&|]*-[a-z]*f'; then
  mogger_re "$LC" 'git[[:space:]]+([^;&|]*[[:space:]])?clean[[:space:]]+[^;&|]*(-[a-z]*n|--dry-run)' || block "blocked git clean -f" "git clean -f (deletes untracked files)"
fi

mogger_re "$LC" 'git[[:space:]]+([^;&|]*[[:space:]])?(checkout|restore)[[:space:]]+(--[[:space:]]+)?\.([[:space:]]|$)' && block "blocked git checkout/restore ." "git checkout/restore . (throws away every uncommitted change)"
# --no-verify skips the repo's own pre-commit and pre-push checks: do not retry a failed commit with it
mogger_re "$LC" 'git[[:space:]]+([^;&|]*[[:space:]])?(commit|push|merge|am|cherry-pick)[[:space:]]+([^;&|]*[[:space:]])?--no-verify' && block "blocked --no-verify" "--no-verify (skips the repo's own checks; fix the failing check instead)"

# 5b. Another AI agent started with its safety checks off
mogger_re "$LC" '(^|[[:space:];&|/])(claude|codex|gemini|aider|cursor-agent|opencode|amp|qwen|copilot)[[:space:]]+([^;&|]*[[:space:]])?(--dangerously-skip-permissions|--dangerously-bypass-approvals-and-sandbox|--yolo|--trust-all-tools|--allow-all-tools|--allow-dangerously-skip-permissions)' && block "blocked an AI agent started with permission checks off" "starting another AI agent with its permission checks turned off"

# 6. Destructive database commands
if mogger_re "$LC" '(^|[[:space:];&|])(psql|mysql|mariadb|sqlite3|sqlcmd|mongosh|duckdb|sqlplus|clickhouse-client|cockroach|redis-cli)([[:space:]]|$)'; then
  mogger_re "$LC" 'drop[[:space:]]+(table|database|schema)|truncate[[:space:]]+(table[[:space:]]+)?[a-z_"]|flushall|flushdb|delete[[:space:]]+from[[:space:]]+[a-z0-9_."]+[[:space:]]*(;|$)' && block "blocked destructive SQL" "destructive database command (DROP, TRUNCATE, DELETE with no WHERE, FLUSH)"
fi
mogger_re "$LC" '(^|[[:space:];&|])dropdb[[:space:]]|prisma[[:space:]]+migrate[[:space:]]+reset|db:(drop|reset)' && block "blocked database reset" "database drop or reset"

exit 0
