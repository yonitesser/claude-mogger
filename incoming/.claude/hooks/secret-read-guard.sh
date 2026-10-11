#!/usr/bin/env bash
# PreToolUse hook — matches: Read|Grep|Glob|Bash
# Blocks (exit 2) reading files that hold secrets: .env, ssh keys, cloud and
# registry credentials, private keys. Reading them would copy the secret into
# the chat. secret-guard.sh already blocks WRITING .env; this is the read side.
# Also blocks dumping every environment variable and echoing secret-named ones.
# Text matching, so it can be bypassed on purpose; a seat belt, not a sandbox.
# Allowed: .env.example/.sample/.template/.dist, public keys (*.pub), ls/chmod.
# Escape hatch: MOGGER_SECRET_READ=off.

source "$(dirname "$0")/lib.sh"
set -f   # no filename expansion while splitting words
[ "${MOGGER_SECRET_READ:-on}" = "off" ] && exit 0

INPUT=$(cat)

SENS='(^|/)(\.aws/(credentials|config)|\.kube/config|\.docker/config\.json|\.npmrc|\.netrc|\.pypirc|\.git-credentials|\.config/gh/hosts\.yml|id_(rsa|ed25519|ecdsa|dsa)|\.env(\.[A-Za-z0-9_-]+)?)$|(^|/)(\.ssh|\.gnupg)/.|\.(pem|key|p12|pfx|jks|keystore)$'
SAFE='\.pub$|(^|/)known_hosts$|(^|/)\.env\.(example|sample|template|dist)$'

is_sens() {  # is_sens <path-like text>
  local t="$1"
  t="${t%/}"
  [ -z "$t" ] && return 1
  [[ "$t" =~ $SAFE ]] && return 1
  [[ "$t" =~ $SENS ]]
}

block() {  # block <what>
  mogger_event block "blocked a read of a secret file"
  echo "BLOCKED: reading '$1' would copy a secret into the chat. Ask the human to check it, or to paste only the part you need. (Human override: MOGGER_SECRET_READ=off.)" >&2
  exit 2
}

# Read / Grep / Glob: look at every path-like field.
for f in .tool_input.file_path .tool_input.path .tool_input.glob .tool_input.pattern; do
  v=$(json_get "$INPUT" "$f")
  [ -n "$v" ] && is_sens "$v" && block "$(basename "$v")"
done

# Bash
CMD=$(json_get "$INPUT" '.tool_input.command')
[ -z "$CMD" ] && exit 0
CLEAN=$(printf '%s' "$CMD" | tr -d "\"'\`")

VERBS=' cat less more head tail grep egrep fgrep rg ag awk sed cut sort uniq strings xxd od hexdump base64 nl tee bat jq curl wget scp rsync nc openssl tar zip zcat '
while IFS= read -r seg; do
  [ -z "$seg" ] && continue
  verb=0; hit=""
  case "$seg" in *"< "*|*"<"[~./\$]*) verb=1 ;; esac
  for w in $seg; do
    case "$VERBS" in *" $w "*) verb=1 ;; esac
    for tok in $(printf '%s' "$w" | tr '=<>@:' '     '); do
      is_sens "$tok" && hit="$tok"
    done
  done
  [ "$verb" = 1 ] && [ -n "$hit" ] && block "$(basename "$hit")"
done <<<"$(printf '%s' "$CLEAN" | tr ';|&' '\n\n\n')"

# Environment dumps and echoing secret-named variables
if printf '%s' "$CLEAN" | grep -qE '(^|[;&|])[[:space:]]*(printenv|env|export[[:space:]]+-p)[[:space:]]*($|[;&|])|/proc/(self|[0-9]+)/environ'; then
  block "the whole environment"
fi
if printf '%s' "$CLEAN" | grep -qiE '(echo|printf)[^;&|]*\$\{?[A-Za-z0-9_]*(SECRET|TOKEN|PASSWORD|PASSWD|API_?KEY|PRIVATE_?KEY)'; then
  block "a secret variable"
fi

exit 0
