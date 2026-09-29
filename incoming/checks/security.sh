#!/usr/bin/env bash
# security.sh - app-security scan for vibe-coded projects. REPORT-ONLY.
#
# Usage: bash scripts/checks/security.sh [project-dir]     (default: .)
#
# Output contract (shared with the other scripts/checks/*.sh):
#   one line per finding:  LEVEL|check-id|message      LEVEL = PASS WARN FAIL SKIP
#   every check-id prints at least one PASS or SKIP when it finds nothing,
#   every finding carries file:line evidence taken from the real file content,
#   heuristics say "heuristic" in the message. ALWAYS exits 0. Never writes to
#   the project (temp files live in a mktemp dir). Skips node_modules, .git,
#   dist, build, venv and similar. Secret values are never printed.
#
# What it looks at (grep-based, so it is fast but not a real SAST tool):
#   secrets-*   secret-looking env vars behind browser prefixes, server secrets
#               referenced from client code, vendor key literals
#   input-*     request bodies used with no schema library in the project
#   auth-*      routes with no auth reference, Supabase tables without RLS,
#               Firebase rules that allow everything, lookups by URL id with
#               no owner check
#   inject-*    SQL built from request data, unsafe HTML sinks, eval/exec,
#               shell=True
#   config-*    CORS * + credentials, TLS verification off, debug on, JWT
#               secret literals, session cookies without flags, tracked .env
#   pay-*       hand-rolled card handling, Luhn code, unsigned Stripe webhooks
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$HERE/../../hooks/scripts/secret-patterns.sh" ]; then . "$HERE/../../hooks/scripts/secret-patterns.sh" 2>/dev/null
elif [ -f "$HERE/../.claude/hooks/secret-patterns.sh" ]; then . "$HERE/../.claude/hooks/secret-patterns.sh" 2>/dev/null; fi
type mogger_is_placeholder >/dev/null 2>&1 || mogger_is_placeholder() {
  case "$1" in *xxx*|*your-*|*your_*|*example*|*changeme*|*placeholder*|*dummy*|*fake*) return 0;; esac
  return 1
}

out() { printf '%s|%s|%s\n' "$1" "$2" "$3"; }

DIR="${1:-.}"
[ -d "$DIR" ] || { out SKIP security "not a directory: $DIR"; exit 0; }
cd "$DIR" 2>/dev/null || { out SKIP security "cannot enter $DIR"; exit 0; }
T=$(mktemp -d 2>/dev/null) || { out SKIP security "mktemp failed; cannot scan"; exit 0; }
trap 'rm -rf "$T"' EXIT
MAXSHOW="${MOGGER_SECURITY_MAX:-5}"
SQ="'"; DQ='"'; BT='`'

# ---------- file lists ----------
find . -type d \( -name node_modules -o -name .git -o -name dist -o -name build -o -name venv -o -name .venv \
  -o -name __pycache__ -o -name .next -o -name .nuxt -o -name target -o -name coverage -o -name .cache \
  -o -name site-packages -o -name vendor -o -name .claude -o -name .turbo -o -name .svelte-kit \) -prune \
  -o -type f -size -400k -print 2>/dev/null | head -8000 | sed 's#^\./##' > "$T/all"

: > "$T/src"; : > "$T/cfg"; : > "$T/envf"; : > "$T/sql"; : > "$T/rules"; : > "$T/model"
while IFS= read -r f; do
  [ -z "$f" ] && continue
  b="${f##*/}"
  case "$f" in
    test/*|tests/*|*/test/*|*/tests/*|*/__tests__/*|*.test.*|*.spec.*|*_test.*|test_*|*/test_*|e2e/*|*/e2e/*|*/fixtures/*|*/__mocks__/*|conftest.py|*/cypress/*) continue;;
  esac
  case "$b" in
    package-lock.json|yarn.lock|pnpm-lock.yaml|npm-shrinkwrap.json|composer.lock|*.min.js|*.min.css|*.map|*.lock|*.svg|*.png|*.jpg|*.ico|*.woff*) continue;;
    .env.example|.env.sample|.env.template|.env|.env.*|*.env) echo "$f" >> "$T/envf"; continue;;
    *.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs|*.py|*.vue|*.svelte|*.html|*.htm|*.php|*.rb|*.go|*.java|*.astro) echo "$f" >> "$T/src";;
    *.json|*.yml|*.yaml|*.toml|*.ini|*.cfg|*.sh|Dockerfile*|Procfile|*.conf) echo "$f" >> "$T/cfg";;
    *.sql) echo "$f" >> "$T/sql"; echo "$f" >> "$T/model";;
    *.prisma) echo "$f" >> "$T/model";;
    *.rules) echo "$f" >> "$T/rules";;
  esac
done < "$T/all"
cat "$T/src" >> "$T/cfg"                         # cfg = src + config-type files
cat "$T/cfg" "$T/envf" > "$T/cfgenv"
cat "$T/src" >> "$T/model"
: > "$T/useclient"
while IFS= read -r f; do
  head -5 "$f" 2>/dev/null | grep -qE "^[[:space:]]*[${DQ}${SQ}]use client[${DQ}${SQ}]" && echo "$f" >> "$T/useclient"
done < "$T/src"

# ---------- helpers ----------
is_comment() { local re='^[[:space:]]*(//|#|[*]|/[*]|<!--|--)'; [[ $1 =~ $re ]]; }

# emit_hits <id> <level> <msg> <ere> <listfile> [filter-fn] [grep-flags]
# Filter fns get (file line content); return 1 to drop; may set LVL / XTRA.
emit_hits() {
  local id="$1" lvl="$2" msg="$3" re="$4" list="$5" filter="${6:-}" flags="${7:--nHIE}"
  local n=0 h f rest ln content ex
  [ -s "$list" ] || return 0
  tr '\n' '\0' < "$list" | xargs -0 grep $flags -e "$re" -- 2>/dev/null | head -300 > "$T/h"
  while IFS= read -r h; do
    f="${h%%:*}"; rest="${h#*:}"; ln="${rest%%:*}"; content="${rest#*:}"
    case "$flags" in *o*) is_comment "$(sed -n "${ln}p" "$f" 2>/dev/null)" && continue;; *) is_comment "$content" && continue;; esac
    LVL="$lvl"; XTRA=""
    if [ -n "$filter" ]; then "$filter" "$f" "$ln" "$content" || continue; fi
    n=$((n+1)); : > "$T/f.$id"
    if [ "$n" -le "$MAXSHOW" ]; then
      if [ "${NOEX:-0}" = 1 ]; then out "$LVL" "$id" "$msg ($f:$ln)$XTRA"
      else
        ex=$(printf '%s' "$content" | sed -E 's/^[[:space:]]+//' | cut -c1-90 | tr '|' '/')
        out "$LVL" "$id" "$msg ($f:$ln): $ex$XTRA"
      fi
    fi
  done < "$T/h"
  [ "$n" -gt "$MAXSHOW" ] && out "$lvl" "$id" "...and $((n-MAXSHOW)) more like it (rerun with MOGGER_SECURITY_MAX=50 to list)"
  return 0
}
pass_if_clean() { [ -e "$T/f.$1" ] || out PASS "$1" "$2"; }
grep_files() {  # grep_files <ere> <list> [flags] -> matching file names
  [ -s "$2" ] || return 0
  tr '\n' '\0' < "$2" | xargs -0 grep -lI${3:-E} -e "$1" -- 2>/dev/null
}
NSRC=$(wc -l < "$T/src" | tr -d ' ')

# ---------- secrets ----------
env_class() {  # public-prefixed name -> allow | strong | weak | none
  local r="$1"
  r="${r#NEXT_PUBLIC_}"; r="${r#VITE_}"; r="${r#REACT_APP_}"; r="${r#EXPO_PUBLIC_}"
  case "$r" in
    *ANON*|*PUBLISHABLE*|*SITE_KEY*|*PUBLIC_KEY*|*PUBLIC_TOKEN*|*MAPBOX*|*RECAPTCHA*|*FIREBASE*|*POSTHOG*|*GOOGLE_MAPS*|*ANALYTICS*|*SENTRY*|*CLIENT_KEY*|*TURNSTILE*|*SEARCH_KEY*|*APP_KEY*|*PK_*|*_PK|*KEYBOARD*|*KEYCLOAK*|*KEYFRAME*) echo allow; return;;
  esac
  case "$r" in
    *SECRET*|*PASSWORD*|*PASSWD*|*PRIVATE*|*SERVICE_ROLE*|*SERVICE_KEY*|*OPENAI*|*ANTHROPIC*|*AWS_*|*GITHUB*|*DATABASE*|*MONGO*|*ADMIN_KEY*|*MASTER_KEY*|*_SK|*_SK_*) echo strong; return;;
  esac
  case "_${r}_" in *_KEY_*|*_TOKEN_*|*_KEYS_*|*APIKEY*) echo weak; return;; esac
  echo none
}
f_pubenv() {
  local c; c=$(env_class "$3")
  case "$c" in
    strong) LVL=FAIL; XTRA=" - name says secret but this prefix ships it to the browser";;
    weak) LVL=WARN; XTRA=" - heuristic: KEY/TOKEN behind a browser prefix; fine only if it is a public/publishable key";;
    *) return 1;;
  esac
  return 0
}
PUBRE="(NEXT_PUBLIC|VITE|REACT_APP|EXPO_PUBLIC)_[[:upper:][:digit:]_]*(KEY|SECRET|TOKEN|PASSWORD|PASSWD|PRIVATE)[[:upper:][:digit:]_]*"
NOEX=1 emit_hits secrets-public-env FAIL "secret-looking env var with a browser-exposed prefix" "$PUBRE" "$T/cfgenv" f_pubenv -nHIoE
pass_if_clean secrets-public-env "no secret-looking NEXT_PUBLIC_/VITE_/REACT_APP_/EXPO_PUBLIC_ variables in $NSRC source files and env files"

: > "$T/client"
while IFS= read -r f; do
  case "$f" in */api/*|api/*|*.server.*|*/server/*|server/*|*/pages/api/*) continue;; esac
  if grep -qxF "$f" "$T/useclient"; then echo "$f" >> "$T/client"; continue; fi
  case "$f" in public/*|*/public/*|*.html|*.htm|components/*|*/components/*)
    grep -qE "^[[:space:]]*[${DQ}${SQ}]use server[${DQ}${SQ}]|server-only" "$f" 2>/dev/null || echo "$f" >> "$T/client";;
  esac
done < "$T/src"
f_srvenv() {
  local name="${3#process.env.}"
  case "$name" in NEXT_PUBLIC_*|VITE_*|REACT_APP_*|EXPO_PUBLIC_*|NODE_ENV) return 1;; esac
  case "$name" in *SECRET*|*PASSWORD*|*PRIVATE*|*SERVICE_ROLE*|*KEY*|*TOKEN*|*DATABASE_URL*|*DB_URL*|*CONNECTION_STRING*) ;; *) return 1;; esac
  [ "$(env_class "$name")" = allow ] && return 1
  if grep -qxF "$1" "$T/useclient"; then LVL=FAIL; XTRA=" - file is a client component";
  else case "$1" in public/*|*/public/*|*.html|*.htm) LVL=FAIL; XTRA=" - file is served to the browser";;
       *) LVL=WARN; XTRA=" - heuristic: components/ may be a server component";; esac; fi
  return 0
}
NOEX=1 emit_hits secrets-client-server-var FAIL "server-side secret env var referenced in client code" "process[.]env[.][[:upper:][:digit:]_]+" "$T/client" f_srvenv -nHIoE
pass_if_clean secrets-client-server-var "no server secret env vars referenced from $(wc -l < "$T/client" | tr -d ' ') client files"

f_lit() {
  local m="$3"
  mogger_is_placeholder "$m" && return 1
  case "$m" in sk-ant-*|sk_live_*|rk_live_*|sk-*) case "$m" in sk-ant-*|sk_live_*|rk_live_*) ;; *[0-9]*) ;; *) return 1;; esac;; esac
  XTRA=" - starts '${m:0:6}...'"; return 0
}
LITRE="AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{22,}|sk-ant-[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9_-]{32,}|[sr]k_live_[A-Za-z0-9]{16,}|xox[abprs]-[A-Za-z0-9-]{10,}|-----BEGIN ([A-Z]+ )*PRIVATE KEY-----"
NOEX=1 emit_hits secrets-literal FAIL "hardcoded vendor API key / private key literal" "$LITRE" "$T/cfg" f_lit -nHIoE
pass_if_clean secrets-literal "no vendor key literals in source/config files"

# ---------- input validation ----------
BODYRE="req[.]body|req[.]json[(]|request[.](json|get_json|form|args|data)"
grep_files "$BODYRE" "$T/src" > "$T/bodyfiles"
: > "$T/schemaf"
printf '%s\n' package.json requirements.txt pyproject.toml Pipfile setup.py > "$T/manif"
ls requirements*.txt 2>/dev/null >> "$T/manif"
cat "$T/manif" "$T/src" | sort -u > "$T/schemascan"
SCHEMARE="(^|[^[:alnum:]_-])(zod|joi|yup|pydantic|marshmallow|valibot|express-validator|class-validator|ajv|superstruct|typebox|fastapi)([^[:alnum:]_-]|$)"
LIB=""
if [ -s "$T/schemascan" ]; then
  LIB=$(tr '\n' '\0' < "$T/schemascan" | xargs -0 grep -hIoE -e "$SCHEMARE" -- 2>/dev/null | head -1 | sed -E 's/^[^[:alnum:]]*//; s/[^[:alnum:]]*$//')
fi
if [ ! -s "$T/bodyfiles" ]; then out PASS input-validation "no request-body handling found in $NSRC source files"
elif [ -n "$LIB" ]; then out PASS input-validation "schema/validation library present ($LIB); per-route use not verified (heuristic)"
else emit_hits input-validation WARN "heuristic: request data used and no schema library (zod/joi/yup/pydantic/marshmallow/valibot/express-validator) in project" "$BODYRE" "$T/src"; fi

# ---------- auth ----------
AUTHREF="auth([^o]|$)|authoriz|session|jwt|bearer|login_required|middleware|passport|clerk|getuser|currentuser|verify_?token|requireuser|permission|Depends[(]|token"
SIGNAL="next-auth|@clerk|passport|lucia|supabase[.]auth|firebase-admin|flask_login|flask_jwt|flask-jwt|jsonwebtoken|@auth/|better-auth|auth0|getServerSession|login_required|OAuth2PasswordBearer|fastapi[.]security|django[.]contrib[.]auth|@kinde|@supabase/ssr|iron-session|express-session"
ROUTERE="(app|router|server|api|route)[.](get|post|put|patch|delete|all)[(][[:space:]]*[${DQ}${SQ}${BT}]/|@[[:alnum:]_]+[.](route|get|post|put|patch|delete)[(]"
MARKER="NextRequest|NextResponse|res[.](json|status|send)|Response[.]json|req[.](body|query|params|headers)"
: > "$T/routes"
grep_files "$ROUTERE" "$T/src" >> "$T/routes"
while IFS= read -r f; do
  case "$f" in
    route.ts|route.js|*/route.ts|*/route.js|pages/api/*|*/pages/api/*|api/*|*/api/*)
      grep -qE "$MARKER" "$f" 2>/dev/null && echo "$f" >> "$T/routes";;
  esac
done < "$T/src"
sort -u "$T/routes" > "$T/routes2"
HASMW=""; while IFS= read -r f; do case "${f##*/}" in middleware.ts|middleware.js) HASMW="$f";; esac; done < "$T/src"
SIG=""
[ -s "$T/cfg" ] && SIG=$(tr '\n' '\0' < "$T/cfg" | xargs -0 grep -nHIE -m1 -e "$SIGNAL" -- 2>/dev/null | head -1 | cut -d: -f1,2)
if [ ! -s "$T/routes2" ]; then out SKIP auth-routes "no route handlers found (looked for express/flask/fastapi decorators and Next api/route files)"
elif [ -n "$SIG" ] || [ -n "$HASMW" ]; then
  out PASS auth-routes "auth signal in project (${SIG:-$HASMW}); per-route coverage not verified (heuristic)"
else
  n=0
  while IFS= read -r f; do
    case "$f" in *health*|*login*|*signin*|*signup*|*register*|*auth*|*webhook*|*callback*|*public*|*ping*) continue;; esac
    grep -qiE "$AUTHREF" "$f" 2>/dev/null && continue
    ln=$(grep -nE -m1 -e "$ROUTERE|$MARKER" "$f" 2>/dev/null | cut -d: -f1); : > "$T/f.auth-routes"
    n=$((n+1)); [ "$n" -le "$MAXSHOW" ] && out WARN auth-routes "heuristic: route handler with no auth/session/middleware reference in the file or project ($f:${ln:-1})"
  done < "$T/routes2"
  pass_if_clean auth-routes "every route file references auth or is a public-looking route (login/health/webhook)"
fi

# Supabase RLS
: > "$T/tabs"; : > "$T/rls"; : > "$T/sbsql"
while IFS= read -r f; do
  case "$f" in *supabase*) echo "$f" >> "$T/sbsql";; esac
done < "$T/sql"
if [ ! -s "$T/sbsql" ]; then out SKIP auth-rls "no supabase/ SQL migrations found"
else
  while IFS= read -r f; do
    tr '[:upper:]' '[:lower:]' < "$f" | grep -E 'enable[[:space:]]+row[[:space:]]+level[[:space:]]+security' >> "$T/rls" 2>/dev/null
    grep -niE '^[[:space:]]*create[[:space:]]+table' "$f" 2>/dev/null | while IFS= read -r l; do
      ln="${l%%:*}"; txt=$(printf '%s' "${l#*:}" | tr '[:upper:]' '[:lower:]')
      nm=$(printf '%s' "$txt" | sed -E 's/^[[:space:]]*create[[:space:]]+table[[:space:]]+(if[[:space:]]+not[[:space:]]+exists[[:space:]]+)?//; s/^public[.]//; s/[[:space:]("].*$//; s/"//g')
      printf '%s:%s:%s\n' "$f" "$ln" "$nm" >> "$T/tabs"
    done
  done < "$T/sbsql"
  while IFS= read -r l; do
    f="${l%%:*}"; r="${l#*:}"; ln="${r%%:*}"; nm="${r#*:}"
    [ -z "$nm" ] && continue
    case "$nm" in *.*) continue;; esac
    grep -qE "(^|[^[:alnum:]_])${nm}([^[:alnum:]_]|$)" "$T/rls" && continue
    : > "$T/f.auth-rls"; out FAIL auth-rls "table '$nm' created without 'enable row level security' in any supabase SQL - anyone holding the anon key can read/write it ($f:$ln)"
  done < "$T/tabs"
  pass_if_clean auth-rls "every table created in supabase SQL has enable row level security"
fi

# Firebase rules
if [ ! -s "$T/rules" ]; then out SKIP auth-firebase-rules "no *.rules files found"
else
  emit_hits auth-firebase-rules FAIL "security rules allow anyone to write" "allow[[:space:]]+[[:lower:], ]*(write|create|update|delete)[[:lower:], ]*:[[:space:]]*if[[:space:]]+true" "$T/rules"
  emit_hits auth-firebase-rules WARN "security rules are in open test mode (expiring blanket allow)" "allow[[:space:]]+[[:lower:], ]+:[[:space:]]*if[[:space:]]+request[.]time[[:space:]]*<" "$T/rules"
  emit_hits auth-firebase-rules WARN "heuristic: public read on everything (fine only for public data)" "allow[[:space:]]+read[[:space:]]*:[[:space:]]*if[[:space:]]+true" "$T/rules"
  pass_if_clean auth-firebase-rules "no open 'if true' write rules"
fi

# lookup by URL id without owner check
OWNERRE="user_?id|owner|session[.]user|req[.]user|request[.]user|auth[(]|created_?by|author_?id|getServerSession|currentUser"
f_idor() { grep -qiE "$OWNERRE" "$1" 2>/dev/null && return 1; XTRA=" - heuristic: no owner/user reference anywhere in this file"; return 0; }
IDRE="(findById|findByIdAndUpdate|findByIdAndDelete|findOne|findUnique|findFirst|findOneAndUpdate|findOneAndDelete|deleteOne)[[:alnum:]_]*[(].*(req[.]params|req[.]query|params[.][[:alnum:]_]+)|where:[[:space:]]*[{][[:space:]]*id:[[:space:]]*(Number[(]|parseInt[(])?[[:space:]]*(req[.]params|req[.]query|params[.]|ctx[.]params)|[.]eq[(][${DQ}${SQ}]id[${DQ}${SQ}],[[:space:]]*(req[.]params|params[.])|objects[.](get|filter)[(](pk|id)=(pk|id|kwargs|request)"
emit_hits auth-idor WARN "record fetched by an id taken from the request, no owner check" "$IDRE" "$T/src" f_idor
pass_if_clean auth-idor "no id-from-request lookups without owner reference found"

# ---------- injection / XSS ----------
REQ="(req[.](body|query|params)|request[.](args|form|json|data|GET|POST|values|query_params|path_params)|params[.][[:alnum:]_]|searchParams)"
NQ="[^${DQ}${SQ}${BT}]"
SQLKW="(select[[:space:]]${NQ}*from[[:space:]]|insert[[:space:]]+into[[:space:]]|update[[:space:]]+[[:alnum:]_.]+[[:space:]]+set[[:space:]]|delete[[:space:]]+from[[:space:]])"
SQLRE="${SQLKW}.*([\$][{][^}]*${REQ}|[+][[:space:]]*${REQ}|[.]format[(][^)]*${REQ}|[%][[:space:]]*[(]?[[:space:]]*${REQ})|(^|[^[:alnum:]_])f[${DQ}${SQ}]${NQ}*${SQLKW}${NQ}*[{][^}]*${REQ}"
f_sqlreq() { XTRA=" - request data is spliced into the SQL text (use placeholders)"; return 0; }
emit_hits inject-sql FAIL "SQL string built from request data" "$SQLRE" "$T/src" f_sqlreq -nHIEi
f_sqlwarn() { XTRA=" - heuristic: interpolated SQL text; safe only if every value is a constant"; return 0; }
emit_hits inject-sql WARN "interpolation inside a query/execute call" "(query|execute|executemany|raw|queryRawUnsafe|executeRawUnsafe)[(][[:space:]]*(${BT}[^${BT}]*[\$][{]|f[${DQ}${SQ}])" "$T/src" f_sqlwarn
pass_if_clean inject-sql "no SQL built from request data by concatenation/interpolation on a single line (multi-line queries not checked)"

f_html() { grep -qiE "dompurify|sanitize" "$1" 2>/dev/null && return 1; XTRA=" - heuristic: non-literal HTML with no sanitizer in file"; return 0; }
emit_hits inject-xss WARN "dangerouslySetInnerHTML with a non-literal value" "dangerouslySetInnerHTML[^_]*__html:[[:space:]]*[^[:space:]${DQ}${SQ}${BT}]" "$T/src" f_html
emit_hits inject-xss WARN "innerHTML/outerHTML assigned a non-literal value" "[.](inner|outer)HTML[[:space:]]*[+]?=[[:space:]]*[^[:space:]${DQ}${SQ}${BT}=]" "$T/src" f_html
emit_hits inject-xss WARN "innerHTML assigned a template with interpolation" "[.](inner|outer)HTML[[:space:]]*[+]?=[[:space:]]*${BT}[^${BT}]*[\$][{]" "$T/src" f_html
pass_if_clean inject-xss "no non-literal innerHTML/dangerouslySetInnerHTML"

PFX="^([^${DQ}${SQ}${BT}]*[^[:alnum:]_.])?"
f_ev() { case "$3" in *req.*|*request.*|*params*|*body*|*query*) LVL=FAIL; XTRA=" - request data reaches it";; *) XTRA=" - heuristic: variable argument";; esac; return 0; }
emit_hits inject-eval WARN "eval/exec with a non-literal argument" "${PFX}(eval|exec)[(][[:space:]]*[^${DQ}${SQ}${BT}[:space:])]" "$T/src" f_ev
emit_hits inject-eval WARN "new Function with a non-literal argument" "${PFX}new[[:space:]]+Function[(][[:space:]]*[^${DQ}${SQ}${BT}[:space:])]" "$T/src" f_ev
emit_hits inject-eval WARN "shell command built with interpolation/concatenation" "(exec|execSync)[(][[:space:]]*(${BT}[^${BT}]*[\$][{]|[${DQ}${SQ}][^${DQ}${SQ}]*[${DQ}${SQ}][[:space:]]*[+])|(os[.]system|os[.]popen|subprocess[.][[:alpha:]_]+)[(][[:space:]]*f[${DQ}${SQ}]" "$T/src" f_ev
f_shell() { case "$1" in *.py) ;; *) return 1;; esac; XTRA=" - shell=True runs the string through a shell"; return 0; }
emit_hits inject-eval WARN "shell=True" "shell[[:space:]]*=[[:space:]]*True" "$T/src" f_shell
pass_if_clean inject-eval "no eval/new Function/exec with variables and no shell=True"

# ---------- config ----------
f_cors() { grep -qiE "(credentials|allow-credentials|CORS_ALLOW_CREDENTIALS|supports_credentials)[^,;]{0,20}(true|True)" "$1" 2>/dev/null || return 1; XTRA=" - wildcard origin together with credentials in the same file"; return 0; }
emit_hits config-cors FAIL "CORS allows any origin and credentials" "(origin|origins|allow-origin)[^*]{0,30}[${DQ}${SQ}][*][${DQ}${SQ}]|CORS_ALLOW_ALL_ORIGINS[[:space:]]*=[[:space:]]*True|origin[[:space:]]*:[[:space:]]*true" "$T/src" f_cors -nHIEi
pass_if_clean config-cors "no wildcard-origin CORS combined with credentials"

f_tls() { case "$3" in *localhost*|*127.0.0.1*) return 1;; esac; return 0; }
emit_hits config-tls FAIL "TLS certificate verification disabled" "verify[[:space:]]*=[[:space:]]*False|rejectUnauthorized[[:space:]]*:[[:space:]]*false|NODE_TLS_REJECT_UNAUTHORIZED[^[:alnum:]]{0,4}0|InsecureSkipVerify[[:space:]]*:[[:space:]]*true" "$T/cfgenv" f_tls
pass_if_clean config-tls "no TLS verification switched off"

f_dbgpy() { case "$1" in *.py) ;; *) return 1;; esac; case "$1" in *prod*) LVL=FAIL;; esac; XTRA=" - heuristic: make sure production overrides this"; return 0; }
emit_hits config-debug WARN "debug mode enabled in code" "^[[:space:]]*DEBUG[[:space:]]*=[[:space:]]*True|app[.]run[(].*debug[[:space:]]*=[[:space:]]*True|FLASK_DEBUG[[:space:]]*=[[:space:]]*(1|true)" "$T/cfg" f_dbgpy
f_dbgprod() { case "$1" in *prod*) return 0;; esac; return 1; }
emit_hits config-debug FAIL "debug flag on in a production-named config" "(^|[^[:alnum:]_])[Dd][Ee][Bb][Uu][Gg][${DQ}${SQ}]?[[:space:]]*[:=][[:space:]]*[${DQ}${SQ}]?(true|True|1)([^[:alnum:]]|$)" "$T/cfgenv" f_dbgprod
pass_if_clean config-debug "no debug=True in code or production-named configs"

NOEX=1 emit_hits config-jwt FAIL "JWT signing secret is a string literal" "(jwt|jsonwebtoken)[.](sign|verify|encode|decode)[(][^)]*,[[:space:]]*[${DQ}${SQ}][^${DQ}${SQ}]+[${DQ}${SQ}]|jwt_?secret[[:alnum:]_]*[[:space:]]*[:=][[:space:]]*[${DQ}${SQ}][^${DQ}${SQ}]{3,}[${DQ}${SQ}]|JWT_SECRET[^|]*[|][|][[:space:]]*[${DQ}${SQ}]" "$T/src" "" -nHIEi
pass_if_clean config-jwt "no JWT secret literals"

f_cookie() {
  local w; w=$(sed -n "${2},$(($2+7))p" "$1" 2>/dev/null)
  printf '%s' "$w" | grep -qiE "session|token|auth|jwt|sid|login" || return 1
  local h=1 s=1
  printf '%s' "$w" | grep -qi httponly && h=0
  printf '%s' "$w" | grep -qi secure && s=0
  [ $h -eq 0 ] && [ $s -eq 0 ] && return 1
  XTRA=" - heuristic: no httpOnly/secure in the next 8 lines (options may be set elsewhere)"; return 0
}
emit_hits config-cookies WARN "session/auth cookie set without httpOnly+secure" "(res[.]cookie|cookies[(][)][.]set|cookies[.]set|set_cookie|setCookie|response[.]cookie)[(]" "$T/src" f_cookie
pass_if_clean config-cookies "no session/auth cookies set without flags"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  while IFS= read -r f; do
    case "${f##*/}" in .env.example|.env.sample|.env.template|.env.dist|.env.defaults) continue;; .env|.env.*|*.env) : > "$T/f.config-env-tracked"; out FAIL config-env-tracked "env file is tracked by git ($f, from git ls-files) - secrets are in history";; esac
  done < <(git ls-files 2>/dev/null)
  pass_if_clean config-env-tracked "no .env file tracked by git"
else out SKIP config-env-tracked "not a git repository, cannot tell what is tracked"; fi

# ---------- payments ----------
CARDN="(^|[^[:alnum:]_])(card_?number|card_?num|card_?no|cc_?num|cc_?number|cvv2?|cvc2?|card_?cvv|card_?cvc)([^[:alnum:]_]|$)"
f_card() {
  printf '%s' "$3" | grep -qiE "console[.](log|info|debug)|logger[.]|logging[.]|print[(]|localStorage|sessionStorage|fetch[(]|axios|[.]post[(]|[.]save[(]|[.]create[(]|insert|writeFile|requests[.]post|[.]put[(]|cookie|redis|[.]set[(]" || return 1
  printf '%s' "$3" | grep -qiE "stripe|elements[.]create|CardNumberElement|CardCvcElement|CardExpiryElement|useElements|getElement" && return 1
  XTRA=" - card data is being stored/logged/sent by your own code"; return 0
}
emit_hits pay-card-data FAIL "card number/CVV handled by hand-rolled code" "$CARDN" "$T/src" f_card -nHIEi
f_luhn() { XTRA=" - hand-rolled card validation means you are touching raw card numbers"; return 0; }
emit_hits pay-luhn FAIL "Luhn check implementation" "(function|def|const|let|var|func|fn)[[:space:]]+[[:alnum:]_]*luhn" "$T/src" f_luhn -nHIEi
pass_if_clean pay-luhn "no Luhn implementations"
# card fields in models/schemas
while IFS= read -r f; do
  grep -qiE "create[[:space:]]+table|model[[:space:]]+[[:alnum:]_]+[[:space:]]*[{]|models[.]Model|Schema[(]|@Entity|define[(]|Column[(]" "$f" 2>/dev/null || continue
  cv=$(grep -niE -m1 "(^|[^[:alnum:]_])(cvv2?|cvc2?)([^[:alnum:]_]|$)" "$f" 2>/dev/null | cut -d: -f1)
  nm=$(grep -niE -m1 "(^|[^[:alnum:]_])(card_?number|card_?num|card_?no|cc_?num|cc_?number)([^[:alnum:]_]|$)" "$f" 2>/dev/null | cut -d: -f1)
  ex=$(grep -niE -m1 "expir|exp_?(month|year|date)" "$f" 2>/dev/null | cut -d: -f1)
  if [ -n "$cv" ]; then : > "$T/f.pay-card-data"; out FAIL pay-card-data "database model stores a CVV/CVC field ($f:$cv) - never store it, use your provider's hosted fields"
  elif [ -n "$nm" ] && [ -n "$ex" ]; then : > "$T/f.pay-card-data"; out FAIL pay-card-data "database model stores card number and expiry ($f:$nm, $f:$ex) - store only the provider's token/last4"; fi
done < "$T/model"
pass_if_clean pay-card-data "no card number/CVV handled or stored by your own code"

grep_files "stripe" "$T/src" i > "$T/stripef"
while IFS= read -r f; do
  ev=$(grep -nE -m1 "checkout[.]session[.]completed|payment_intent[.]succeeded|invoice[.]paid|customer[.]subscription|charge[.]succeeded" "$f" 2>/dev/null | cut -d: -f1)
  case "$f" in *webhook*) [ -z "$ev" ] && ev=1;; esac
  [ -z "$ev" ] && continue
  grep -qiE "signature|constructEvent|construct_event|svix|hmac" "$f" 2>/dev/null && continue
  : > "$T/f.pay-webhook"; out WARN pay-webhook "heuristic: Stripe webhook handler with no signature verification (constructEvent / construct_event / stripe-signature) - anyone can POST fake payment events ($f:$ev)"
done < "$T/stripef"
pass_if_clean pay-webhook "no unsigned Stripe webhook handlers found"

exit 0
