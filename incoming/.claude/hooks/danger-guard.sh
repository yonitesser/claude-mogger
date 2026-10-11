#!/usr/bin/env bash
# PreToolUse hook — matches: Bash
# Blocks shell commands that can destroy data or the machine: recursive rm of
# root/home/system dirs, dd/mkfs on devices, curl|sh, chmod 777, git reset
# --hard / clean -f, and destructive SQL (DROP, TRUNCATE, DELETE with no WHERE).
# Plain text matching, so it can be bypassed on purpose; it is a seat belt
# against mistakes, not a sandbox. Fails open on bad input.
# Escape hatch: MOGGER_DANGER_GUARD=off.

source "$(dirname "$0")/lib.sh"
[ "${MOGGER_DANGER_GUARD:-on}" = "off" ] && exit 0

INPUT=$(cat)
CMD=$(json_get "$INPUT" '.tool_input.command')
[ -z "$CMD" ] && exit 0

block() {  # block <short event text> <what was found>
  mogger_event block "$1"
  echo "BLOCKED: $2. This can destroy data or the machine. Ask the human to run it, or to set MOGGER_DANGER_GUARD=off." >&2
  exit 2
}

# Quotes and backticks removed so wrappers like bash -c "rm -rf /" are seen.
CLEAN=$(printf '%s' "$CMD" | tr -d "\"'\`" | sed 's/\${HOME}/$HOME/g')
LC=$(printf '%s' "$CLEAN" | tr 'A-Z' 'a-z')

# 1. rm -r on root, home, cwd, wildcards or system dirs
BAD='^(/|/\*|~|~/|~/\*|\$HOME|\$HOME/|\$HOME/\*|\.|\./|\.\.|\.\./|\*|\./\*|\.\./\*|/(etc|usr|var|bin|sbin|lib|lib64|boot|root|home|opt|dev|proc|sys|System|Library|Users|Applications)/?|/(etc|usr|var|bin|sbin|lib|boot|root|home|opt|Users)/\*|/(home|Users)/[^/]+/?|/(home|Users)/[^/]+/\*)$'
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
done <<<"$(printf '%s' "$CLEAN" | tr ';|&(){}' '\n\n\n\n\n\n\n')"

# 2. Disks and fork bombs
echo "$LC" | grep -qE 'dd[[:space:]]+[^;&|]*of=/dev/' && block "blocked dd to a device" "dd writing to a device"
echo "$LC" | grep -qE '(^|[[:space:];&|])mkfs(\.[a-z0-9]+)?([[:space:]]|$)' && block "blocked mkfs" "mkfs formats a disk"
echo "$LC" | grep -qE '>[[:space:]]*/dev/(sd|nvme|hd|disk|vd)' && block "blocked write to a disk device" "redirect into a disk device"
printf '%s' "$CMD" | grep -qE ':\(\)[[:space:]]*\{' && block "blocked fork bomb" "fork bomb"

# 3. Download piped into a shell
echo "$LC" | grep -qE '(curl|wget)[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(env[[:space:]]+)?(ba|z|da|k|fi)?sh([[:space:]]|$)' && block "blocked curl piped to shell" "download piped into a shell"
echo "$LC" | grep -qE '((ba|z|da|k)?sh|eval)[[:space:]]+(-c[[:space:]]+)?(<\(|\$\()[[:space:]]*(curl|wget)' && block "blocked curl run as shell code" "downloaded script run as code"

# 4. World-writable permissions
echo "$LC" | grep -qE 'chmod[[:space:]]+(-[a-z]+[[:space:]]+)*(0?777|a\+rwx|ugo\+rwx)([[:space:]]|$)' && block "blocked chmod 777" "chmod 777 (anyone can write)"

# 5. Git commands that throw away uncommitted work
echo "$LC" | grep -qE 'git[[:space:]]+([^;&|]*[[:space:]])?reset[[:space:]]+([^;&|]*[[:space:]])?--hard' && block "blocked git reset --hard" "git reset --hard (drops uncommitted work)"
if echo "$LC" | grep -qE 'git[[:space:]]+([^;&|]*[[:space:]])?clean[[:space:]]+[^;&|]*-[a-z]*f'; then
  echo "$LC" | grep -qE 'git[[:space:]]+([^;&|]*[[:space:]])?clean[[:space:]]+[^;&|]*(-[a-z]*n|--dry-run)' || block "blocked git clean -f" "git clean -f (deletes untracked files)"
fi

# 6. Destructive database commands
if echo "$LC" | grep -qE '(^|[[:space:];&|])(psql|mysql|mariadb|sqlite3|sqlcmd|mongosh|duckdb|sqlplus|clickhouse-client|cockroach|redis-cli)([[:space:]]|$)'; then
  echo "$LC" | grep -qE 'drop[[:space:]]+(table|database|schema)|truncate[[:space:]]+(table[[:space:]]+)?[a-z_"]|flushall|flushdb|delete[[:space:]]+from[[:space:]]+[a-z0-9_."]+[[:space:]]*(;|$)' && block "blocked destructive SQL" "destructive database command (DROP, TRUNCATE, DELETE with no WHERE, FLUSH)"
fi
echo "$LC" | grep -qE '(^|[[:space:];&|])dropdb[[:space:]]|prisma[[:space:]]+migrate[[:space:]]+reset|db:(drop|reset)' && block "blocked database reset" "database drop or reset"

exit 0
