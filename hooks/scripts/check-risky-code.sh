#!/usr/bin/env bash
# PostToolUse - matcher: Edit|Write
# Blocks (exit 2) only the HIGH-CONFIDENCE, single-file app-security mistakes in
# the file that was just written; the rest lives in scripts/checks/security.sh.
# Conservative on purpose: a false positive is worse than a miss.
#   1. secret-looking env var behind a browser prefix (NEXT_PUBLIC_/VITE_/
#      REACT_APP_/EXPO_PUBLIC_ + SECRET/PASSWORD/PRIVATE/SERVICE_ROLE/OPENAI...)
#      - publishable/anon/firebase/etc. names are allow-listed
#   2. Firebase rules `allow read, write: if true` (any write with `if true`)
#   3. TLS verification switched off (verify=False, rejectUnauthorized: false,
#      NODE_TLS_REJECT_UNAUTHORIZED=0) - lines mentioning localhost are ignored
#   4. SQL string concatenated/interpolated with request data (req.body|query|
#      params, request.args|form|json...) - parameterized queries never match
#   5. eval( on request data
#   6. client file ("use client", public/, .html) reading a server secret env var
# Test files, comments, docs and lockfiles are ignored.
#
# Fails OPEN: no jq/python3, unreadable/huge file, anything unexpected -> exit 0.
# Escape hatch: MOGGER_CHECK_RISKY=off
source "$(dirname "$0")/lib.sh"

[ "${MOGGER_CHECK_RISKY:-on}" = "off" ] && exit 0

INPUT=$(cat)
FILE=$(json_get "$INPUT" '.tool_input.file_path')
[ -z "$FILE" ] && exit 0
[ -f "$FILE" ] || exit 0
SZ=$(wc -c < "$FILE" 2>/dev/null | tr -d ' ')
[ -n "$SZ" ] && [ "$SZ" -gt 400000 ] && exit 0

BASE="${FILE##*/}"
case "$FILE" in
  */node_modules/*|*/.git/*|*/dist/*|*/build/*|*/venv/*|*/.venv/*) exit 0;;
  test/*|tests/*|*/test/*|*/tests/*|*/__tests__/*|*.test.*|*.spec.*|*_test.*|test_*|*/test_*|*/e2e/*|*/fixtures/*|*/__mocks__/*|*/cypress/*) exit 0;;
esac
KIND=""
case "$BASE" in
  .env.example|.env.sample|.env.template) KIND=env;;
  *.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs|*.vue|*.svelte|*.astro|*.html|*.htm) KIND=js;;
  *.py) KIND=py;;
  *.rules) KIND=rules;;
  *.php|*.rb|*.go|*.java|*.yml|*.yaml|*.json|*.toml|*.sh|Dockerfile*) KIND=other;;
  *) exit 0;;
esac

SQ="'"; DQ='"'; BT='`'
IS_CLIENT=0
if head -5 "$FILE" 2>/dev/null | grep -qE "^[[:space:]]*[${DQ}${SQ}]use client[${DQ}${SQ}]"; then IS_CLIENT=1; fi
case "$FILE" in public/*|*/public/*|*.html|*.htm) IS_CLIENT=1;; esac
case "$FILE" in */api/*|*.server.*) IS_CLIENT=0;; esac

FOUND=""
add() { FOUND="${FOUND}
  - $1 ($FILE:$2)"; }
is_comment() { local re='^[[:space:]]*(//|#|[*]|/[*]|<!--|--)'; [[ $1 =~ $re ]]; }

# scan <ere> <flags> <callback>: callback gets (line content match-line-number)
scan() {
  local re="$1" flags="$2" cb="$3" h ln content
  grep $flags -e "$re" -- "$FILE" 2>/dev/null | head -100 | while IFS= read -r h; do
    ln="${h%%:*}"; content="${h#*:}"
    is_comment "$content" && continue
    "$cb" "$ln" "$content"
  done
}

# subshell output goes through a temp file so `add` can update FOUND
TMPF=$(mktemp 2>/dev/null) || exit 0
trap 'rm -f "$TMPF"' EXIT
rec() { printf '%s|%s\n' "$1" "$2" >> "$TMPF"; }

env_strong() {  # name (with public prefix) -> 0 if clearly a server secret
  local r="$1"
  r="${r#NEXT_PUBLIC_}"; r="${r#VITE_}"; r="${r#REACT_APP_}"; r="${r#EXPO_PUBLIC_}"
  case "$r" in
    *ANON*|*PUBLISHABLE*|*SITE_KEY*|*PUBLIC_KEY*|*PUBLIC_TOKEN*|*MAPBOX*|*RECAPTCHA*|*FIREBASE*|*POSTHOG*|*GOOGLE_MAPS*|*ANALYTICS*|*SENTRY*|*CLIENT_KEY*|*TURNSTILE*|*SEARCH_KEY*|*APP_KEY*|*PK_*|*_PK|*KEYBOARD*|*KEYCLOAK*|*KEYFRAME*) return 1;;
  esac
  case "$r" in
    *SECRET*|*PASSWORD*|*PASSWD*|*PRIVATE*|*SERVICE_ROLE*|*SERVICE_KEY*|*OPENAI*|*ANTHROPIC*|*AWS_*|*GITHUB*|*DATABASE*|*MONGO*|*ADMIN_KEY*|*MASTER_KEY*|*_SK|*_SK_*) ;;
    *) return 1;;
  esac
  case "_${r}_" in *_KEY_*|*_TOKEN_*|*_KEYS_*|*APIKEY*|*SECRET*|*PASSWORD*|*PASSWD*|*PRIVATE*|*SERVICE_ROLE*) return 0;; esac
  return 1
}

cb_pub() {
  local name="$2"
  env_strong "$name" && rec "$1" "secret-looking variable $name uses a browser-exposed prefix, so it is bundled into the client"
}
PUBRE="(NEXT_PUBLIC|VITE|REACT_APP|EXPO_PUBLIC)_[[:upper:][:digit:]_]*(KEY|SECRET|TOKEN|PASSWORD|PASSWD|PRIVATE)[[:upper:][:digit:]_]*"
# -o output is the bare match, prefixed with line number
scan_o() {
  local h ln name
  grep -noE -e "$PUBRE" -- "$FILE" 2>/dev/null | head -100 | while IFS= read -r h; do
    ln="${h%%:*}"; name="${h#*:}"
    line=$(sed -n "${ln}p" "$FILE" 2>/dev/null)
    is_comment "$line" && continue
    cb_pub "$ln" "$name"
  done
}
scan_o

cb_rules() { rec "$1" "Firebase rule lets anyone write (allow ...: if true)"; }
if [ "$KIND" = rules ]; then
  scan "allow[[:space:]]+[[:lower:], ]*(write|create|update|delete)[[:lower:], ]*:[[:space:]]*if[[:space:]]+true" "-nE" cb_rules
fi

cb_tls() { case "$2" in *localhost*|*127.0.0.1*) return;; esac; rec "$1" "TLS certificate verification is disabled"; }
scan "verify[[:space:]]*=[[:space:]]*False|rejectUnauthorized[[:space:]]*:[[:space:]]*false|NODE_TLS_REJECT_UNAUTHORIZED[^[:alnum:]]{0,4}0" "-nE" cb_tls

REQH="(req[.](body|query|params)|request[.](args|form|json|data|GET|POST|values|query_params))"
NQ="[^${DQ}${SQ}${BT}]"
SQLKW="(select[[:space:]]${NQ}*from[[:space:]]|insert[[:space:]]+into[[:space:]]|update[[:space:]]+[[:alnum:]_.]+[[:space:]]+set[[:space:]]|delete[[:space:]]+from[[:space:]])"
SQLRE="${SQLKW}.*([\$][{][^}]*${REQH}|[+][[:space:]]*${REQH}|[.]format[(][^)]*${REQH})|(^|[^[:alnum:]_])f[${DQ}${SQ}]${NQ}*${SQLKW}${NQ}*[{][^}]*${REQH}"
cb_sql() { rec "$1" "SQL text is built from request data (injection); use placeholders / parameterized queries"; }
scan "$SQLRE" "-nEi" cb_sql

cb_eval() { rec "$1" "eval() runs request data as code"; }
scan "^([^${DQ}${SQ}${BT}]*[^[:alnum:]_.])?eval[(][^)]*${REQH}" "-nE" cb_eval

if [ "$IS_CLIENT" -eq 1 ]; then
  cb_cli() {
    local name="${2#process.env.}"
    case "$name" in NEXT_PUBLIC_*|VITE_*|REACT_APP_*|EXPO_PUBLIC_|NODE_ENV) return;; esac
    case "$name" in *SECRET*|*PASSWORD*|*PRIVATE*|*SERVICE_ROLE*|*SERVICE_KEY*|*OPENAI*|*ANTHROPIC*|*DATABASE_URL*|*AWS_SECRET*) ;; *) return;; esac
    rec "$1" "client-side file reads server secret process.env.$name"
  }
  grep -noE -e "process[.]env[.][[:upper:][:digit:]_]+" -- "$FILE" 2>/dev/null | head -100 | while IFS= read -r h; do
    line=$(sed -n "${h%%:*}p" "$FILE" 2>/dev/null); is_comment "$line" && continue
    cb_cli "${h%%:*}" "${h#*:}"
  done
fi

[ -s "$TMPF" ] || exit 0
while IFS='|' read -r ln msg; do add "$msg" "$ln"; done < "$TMPF"
{
  echo "BLOCKED: $FILE has a high-confidence security problem:$FOUND"
  echo "Fix it now: keep secrets server-side (no NEXT_PUBLIC_/VITE_ prefix, no reading them in client files), use parameterized queries, never disable TLS checks, never eval request data, never open Firebase rules to 'if true'. False positive? Set MOGGER_CHECK_RISKY=off for this session and tell the user."
} >&2
exit 2
