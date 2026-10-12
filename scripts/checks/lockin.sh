#!/usr/bin/env bash
# lockin.sh — what ties this project to one platform or tool?
# REPORT-ONLY: never modifies the project. Always exits 0.
#
# Informational tone: lock-in is a trade-off, not always wrong. Firebase or
# Vercel may be exactly the right call. This lists the facts (which vendors,
# how many files, whether the SDK is spread through business logic, and
# whether there is an exit path such as a Dockerfile or documented setup) so
# the owner can decide knowingly. Vendor detection lines are PASS with an
# "info:" prefix; WARN is reserved for "SDK imported all over the code" and
# "no way to run or move this without the vendor".
#
# Usage (from project root):  bash scripts/checks/lockin.sh [project-dir]
# Output: one line per finding  LEVEL|check-id|message   (PASS WARN FAIL SKIP)
set -u
ROOT="${1:-.}"
cd "$ROOT" 2>/dev/null || { printf 'SKIP|lockin-vendors|cannot cd to %s\n' "$ROOT"; exit 0; }
TMP=$(mktemp -d 2>/dev/null || mktemp -d -t mogger)
[ -n "$TMP" ] && [ -d "$TMP" ] || { printf 'SKIP|lockin-vendors|no temp dir available\n'; exit 0; }
trap 'rm -rf "$TMP"' EXIT

out() { printf '%s|%s|%s\n' "$1" "$2" "$3"; }

find . \( -name node_modules -o -name .git -o -name dist -o -name build -o -name venv -o -name .venv \
  -o -name __pycache__ -o -name .next -o -name coverage -o -name target -o -name vendor -o -name .cache \) \
  -prune -o -type f -print 2>/dev/null | sed 's|^\./||' | head -8000 > "$TMP/all"
: > "$TMP/src"; : > "$TMP/deps"
while IFS= read -r f; do
  case "$f" in
    */test/*|*/tests/*|*/__tests__/*|*.test.*|*.spec.*|*/fixtures/*|test/*|tests/*) continue;;
  esac
  case "$f" in
    *package.json|*requirements.txt|*Pipfile|*pyproject.toml|*Gemfile|*composer.json|*go.mod) printf '%s\n' "$f" >> "$TMP/deps";;
    *.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs|*.vue|*.svelte|*.astro|*.py|*.rb|*.php|*.go|*.java|*.kt|*.dart|*.swift) printf '%s\n' "$f" >> "$TMP/src";;
  esac
done < "$TMP/all"
cat "$TMP/src" "$TMP/deps" > "$TMP/srcdeps"

scan() {
  [ -s "$1" ] || return 0
  tr '\n' '\0' < "$1" | xargs -0 grep -H -n -I -i -E -e "$2" -- 2>/dev/null | head -400
}
cite() {
  awk -F: '{ n++; if (n <= 3) s = s (n > 1 ? ", " : "") $1 ":" $2 } END { if (n > 3) s = s " (+" (n - 3) " more)"; print s }'
}
has_file() {  # has_file <path-ere>  -> first matching path
  grep -E "$1" "$TMP/all" | head -1
}

# vendor <name> <import-pkg-ere> <config-file-ere> <extra-code-ere>
#   import-pkg-ere: package names imported (JS from/import/require, Python import/from)
#   config-file-ere: project files that only make sense on that platform
#   extra-code-ere: platform-only API usage that is not an import
NVEND=0; NWARN=0
: > "$TMP/vendorlines"
vendor() {
  local name="$1" pk="$2" cfg="$3" extra="$4" imp cf ex dep nfiles nlist ndirs first msg
  imp=""; cf=""; ex=""
  [ -n "$pk" ] && imp=$(scan "$TMP/src" "(from|import|require[(])[[:space:]]*[(]?.?($pk)")
  [ -n "$cfg" ] && cf=$(grep -E "$cfg" "$TMP/all" | head -5 | tr '\n' ' ')
  [ -n "$extra" ] && ex=$(scan "$TMP/src" "$extra")
  dep=""
  [ -n "$pk" ] && dep=$(scan "$TMP/deps" "[\"'=<>~ ]($pk)")
  [ -z "$imp$cf$ex$dep" ] && return 0
  NVEND=$((NVEND+1))
  nfiles=$(printf '%s\n' "$imp$ex" | grep -v '^$' | cut -d: -f1 | sort -u | wc -l | tr -d ' ')
  nlist=$(printf '%s\n' "$imp$ex" | grep -v '^$' | cite)
  msg="info: $name"
  [ "$nfiles" -gt 0 ] && msg="$msg used in $nfiles source file(s): $nlist"
  [ -n "$dep" ] && msg="$msg; dependency at $(printf '%s\n' "$dep" | head -1 | cut -d: -f1,2)"
  [ -n "$cf" ] && msg="$msg; platform files: ${cf% }"
  out PASS lockin-vendors "$msg (a trade-off, not necessarily a problem)"
  # spread check: SDK imported directly from many places
  if [ -n "$imp" ]; then
    printf '%s\n' "$imp" | cut -d: -f1 | sort -u > "$TMP/impfiles"
    nfiles=$(wc -l < "$TMP/impfiles" | tr -d ' ')
    ndirs=$(sed 's|/[^/]*$||' "$TMP/impfiles" | sort -u | wc -l | tr -d ' ')
    if [ "$nfiles" -ge 3 ] && [ "$ndirs" -ge 2 ]; then
      NWARN=$((NWARN+1))
      first=$(head -3 "$TMP/impfiles" | tr '\n' ' ')
      out WARN lockin-coupling "$name SDK is imported directly in $nfiles files across $ndirs folders ($first...): consider a thin wrapper (one lib/adapter file) so business logic does not import $name directly and a move touches one place [heuristic]"
    fi
  fi
}
vendor "Firebase" 'firebase' 'firebase[.]json|[.]firebaserc|firestore[.]rules|firestore[.]indexes' 'firebase[.](initializeApp|firestore|auth)|getFirestore[(]'
vendor "Supabase" '@supabase/|supabase(-js)?$|supabase-py' 'supabase/config[.]toml|(^|/)supabase/' 'createClient[(].*supabase|supabase[.]from[(]|supabase[.]auth'
vendor "Vercel-only APIs" '@vercel/(kv|blob|postgres|edge-config|edge|og|analytics|speed-insights)' 'vercel[.]json|[.]vercel/' 'runtime[[:space:]]*=[[:space:]]*.edge|VERCEL_[[:upper:]_]+|export const config.*runtime.*edge'
vendor "Netlify" '@netlify/|netlify-lambda' 'netlify[.]toml|netlify/functions/|_redirects$|_headers$' 'netlify/functions'
vendor "Cloudflare Workers" '@cloudflare/|wrangler' 'wrangler[.]toml|wrangler[.]jsonc?$' 'cloudflare:workers|env[.](DB|KV|R2|BUCKET)[.]'
vendor "AWS Amplify / Cognito / DynamoDB" 'aws-amplify|@aws-amplify/|@aws-sdk/client-(dynamodb|cognito)|amazon-cognito|@aws-sdk/lib-dynamodb' 'amplify[.]yml|amplify/' ''
vendor "Convex" 'convex' 'convex/' ''
vendor "Clerk (hosted auth)" '@clerk/' '' ''
vendor "Auth0 (hosted auth)" '@auth0/|auth0-js|auth0' '' ''
vendor "Upstash" '@upstash/' '' ''
vendor "PlanetScale / Neon / Turso serverless DB" '@planetscale/|@neondatabase/|@libsql/|@tursodatabase/' '' ''
vendor "Replit" '@replit/|replit' '(^|/)[.]replit$|replit[.]nix|(^|/)[.]replit' 'REPLIT_DB|REPL_ID|REPL_SLUG'
vendor "Lovable / GPT-Engineer" 'lovable-tagger|gpt-engineer' '(^|/)[.]lovable|lovable[.]toml' 'lovable[.]dev'
vendor "Bolt / StackBlitz" '@stackblitz/' '(^|/)[.]bolt/|(^|/)[.]stackblitzrc' 'bolt[.]new'
vendor "v0 (Vercel)" '' '(^|/)[.]v0/' 'v0[.]dev'
vendor "Base44" '@base44/' '' ''
vendor "Firebase Studio / Project IDX" '' '(^|/)[.]idx/' ''
vendor "Cursor / Windsurf editor config" '' '(^|/)[.]cursorrules|(^|/)[.]cursor/|(^|/)[.]windsurfrules' ''
if [ "$NVEND" -eq 0 ]; then
  if [ -s "$TMP/src" ]; then
    out PASS lockin-vendors "no platform-specific SDKs or config files detected (Firebase, Supabase, Vercel/Netlify/Cloudflare-only APIs, Replit/Lovable/Bolt/v0 configs)"
  else
    out SKIP lockin-vendors "no source files found to scan"
  fi
fi
if [ "$NWARN" -eq 0 ]; then
  if [ "$NVEND" -gt 0 ]; then
    out PASS lockin-coupling "each detected vendor SDK is contained (fewer than 3 importing files, or a single folder)"
  else
    out SKIP lockin-coupling "no vendor SDK detected"
  fi
fi

# ---- can it run without the vendor? ---------------------------------------
if [ -f package.json ]; then
  sl=$(grep -n -E '"start"[[:space:]]*:' package.json | head -1)
  dl=$(grep -n -E '"dev"[[:space:]]*:' package.json | head -1)
  vs=$(grep -n -o -E '"(start|dev|serve)"[[:space:]]*:[[:space:]]*"[^"]*"' package.json | grep -i -E 'vercel|netlify|firebase|wrangler|supabase|replit|amplify' | head -1)
  if [ -n "$vs" ]; then
    out WARN lockin-run "start/dev script needs a vendor CLI at package.json:$(printf '%s' "$vs" | cut -d: -f1): running it elsewhere means replacing that command"
  elif [ -n "$sl" ]; then
    out PASS lockin-run "plain 'npm start' works via package.json:$(printf '%s' "$sl" | cut -d: -f1) (script content is not executed here)"
  elif [ -n "$dl" ]; then
    out PASS lockin-run "'npm run dev' defined at package.json:$(printf '%s' "$dl" | cut -d: -f1); no 'start' script for production"
  else
    out WARN lockin-run "package.json has no start or dev script: how to run this without the vendor's tooling is unclear"
  fi
else
  pf=$(has_file '(^|/)(Procfile|manage[.]py|main[.]py|app[.]py|Makefile|go[.]mod|Gemfile)$')
  if [ -n "$pf" ]; then out PASS lockin-run "entry point/tooling file found: $pf"
  else out SKIP lockin-run "no package.json or known entry-point file to judge a plain run"; fi
fi

df=$(has_file '(^|/)(Dockerfile|docker-compose[.]ya?ml|compose[.]ya?ml)$')
rd=""
for f in README.md readme.md README README.rst; do [ -f "$f" ] && { rd="$f"; break; }; done
setupl=""
[ -n "$rd" ] && setupl=$(grep -n -i -E 'npm install|yarn install|pnpm install|pip install|bundle install|docker|## .*(install|setup|getting started)' "$rd" | head -1 | cut -d: -f1)
if [ -n "$df" ]; then
  out PASS lockin-exit-path "container definition found: $df (a portable way to run this anywhere)"
elif [ -n "$setupl" ]; then
  out PASS lockin-exit-path "no Dockerfile, but $rd:$setupl documents setup steps"
else
  out WARN lockin-exit-path "no Dockerfile and no documented setup steps: moving hosts or handing this to a developer would mean reverse-engineering it (see scripts/checks/docs.sh)"
fi
exit 0
