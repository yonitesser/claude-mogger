#!/usr/bin/env bash
# PreToolUse hook — matches: Read|Grep|Glob|Bash
# Blocks (exit 2) reading files that hold secrets: .env, ssh keys, cloud and
# registry credentials, private keys. Reading them would copy the secret into
# the chat. secret-guard.sh already blocks WRITING .env; this is the read side.
# Also blocks dumping every environment variable and echoing secret-named ones.
# Text matching, so it can be bypassed on purpose; a seat belt, not a sandbox.
# Allowed: .env.example/.sample/.template/.dist, public keys (*.pub), ls/chmod.
# States (MOGGER_SECRET_READ): on = block (default), ask = permission prompt for
# the human, off = allow. Where no prompt can be shown, ask blocks.

source "${0%/*}/lib.sh"
set -f   # no filename expansion while splitting words
STATE=$(mogger_state MOGGER_SECRET_READ on)
[ "$STATE" = "off" ] && exit 0

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
  if [ "$STATE" = ask ] && mogger_can_ask "$INPUT"; then
    mogger_event warn "asked before a read of a secret file"
    mogger_ask_json "Mogger: reading $1 would copy a secret into the chat. Approve only if you want Claude to see it."
    exit 0
  fi
  mogger_event block "blocked a read of a secret file"
  echo "BLOCKED: reading '$1' would copy a secret into the chat. Ask the human to check it, or to paste only the part you need. (Human override: MOGGER_SECRET_READ=off.)" >&2
  exit 2
}

# Read / Grep / Glob: look at every path-like field.
json_fields "$INPUT" .tool_input.file_path .tool_input.path .tool_input.glob .tool_input.pattern .tool_input.command
for v in "${JF[@]:0:4}"; do
  [ -n "$v" ] && is_sens "$v" && block "${v##*/}"
done

# Bash
CMD="${JF[4]}"
[ -z "$CMD" ] && exit 0
CLEAN=${CMD//[\"\'\`]/}   # pure bash from here: this hook runs on every Bash call

VERBS=' cat less more head tail grep egrep fgrep rg ag awk sed cut sort uniq strings xxd od hexdump base64 nl tee bat jq curl wget scp rsync nc openssl tar zip zcat diff source python python3 node ruby perl '
while IFS= read -r seg; do
  [ -z "$seg" ] && continue
  verb=0; hit=""
  case "$seg" in *"< "*|*"<"[~./\$]*) verb=1 ;; esac
  case "$seg" in *git*" show "*|*git*" cat-file "*|*git*" diff "*|*git*" log "*|*git*" blame "*|*git*" grep "*) verb=1 ;; esac
  src=""   # cp/mv leak the file only when it is the SOURCE (copying .env.example to .env.local is fine)
  for w in $seg; do
    w=${w//[()\$]/}
    case "$w" in cp|mv) src=next; continue ;; esac
    if [ "$src" = next ]; then case "$w" in -*) ;; *) src=""; is_sens "$w" && hit="$w" && verb=1 ;; esac; fi
    case "$VERBS" in *" $w "*) verb=1 ;; esac
    wt=${w//[=<>@:()]/ }
    for tok in $wt; do
      is_sens "$tok" && hit="$tok"
    done
  done
  [ "$verb" = 1 ] && [ -n "$hit" ] && block "${hit##*/}"
done <<<"${CLEAN//[;|&]/$'\n'}"

# Environment dumps and echoing secret-named variables
ONE=${CLEAN//$'\n'/;}
if mogger_re "$ONE" '(^|[;&|])[[:space:]]*(printenv|env|export[[:space:]]+-p)[[:space:]]*($|[;&|])|/proc/(self|[0-9]+)/environ'; then
  block "the whole environment"
fi
shopt -s nocasematch
if mogger_re "$ONE" '(echo|printf)[^;&|]*\$\{?[A-Za-z0-9_]*(SECRET|TOKEN|PASSWORD|PASSWD|API_?KEY|PRIVATE_?KEY)'; then
  block "a secret variable"
fi

exit 0
