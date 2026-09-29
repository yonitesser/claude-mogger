#!/usr/bin/env bash
# ship-check.sh — ship-readiness checklist. REPORT-ONLY.
#
# This script NEVER pushes, merges, tags or deploys, and never modifies the
# repo. It only reads and prints PASS / WARN / FAIL / SKIP with evidence.
# The push/deploy gate stays human — this is the list the human reads first.
#
# Usage (from project root):  bash scripts/ship-check.sh [--strict]
# Exit 0 always, except --strict: exit 1 if any check is FAIL.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
[ -f "$HERE/../hooks/scripts/lib.sh" ] && source "$HERE/../hooks/scripts/lib.sh"
type json_get >/dev/null 2>&1 || json_get() { printf ''; }

STRICT=0; [ "${1:-}" = "--strict" ] && STRICT=1
NFAIL=0; NWARN=0; NPASS=0; NSKIP=0
say() {  # say <LEVEL> <name> <evidence>
  case "$1" in FAIL) NFAIL=$((NFAIL+1));; WARN) NWARN=$((NWARN+1));; PASS) NPASS=$((NPASS+1));; SKIP) NSKIP=$((NSKIP+1));; esac
  printf '%-5s %-22s %s\n' "$1" "$2" "$3"
}

INREPO=0; git rev-parse --is-inside-work-tree >/dev/null 2>&1 && INREPO=1
echo "== ship-check (report-only; never pushes or deploys)"

# 1. tests recorded green (same marker require-tests-pass.sh uses)
M=".claude/state/last_test_result.json"
if [ ! -f "$M" ]; then say FAIL tests "no $M — full suite never recorded"
else
  ST=$(json_get "$(cat "$M")" '.status'); SC=$(json_get "$(cat "$M")" '.scope')
  NEWER=$(find . -type f -newer "$M" -not -path './.git/*' -not -path './.claude/state/*' -not -path './node_modules/*' \
    -not -path './.venv/*' -not -path './target/*' -not -path './dist/*' -not -path './build/*' \
    -not -name 'RUNS.md' -not -name 'TASKS.md' 2>/dev/null | head -1)
  if [ "$ST" != "pass" ]; then say FAIL tests "last recorded status '${ST:-missing}'"
  elif [ -n "$SC" ] && [ "$SC" != "full" ]; then say FAIL tests "last pass was scope '$SC', not full"
  elif [ -n "$NEWER" ]; then say FAIL tests "green, but $NEWER changed after it (stale)"
  else say PASS tests "full suite green, not stale"; fi
fi

# 2. smoke
S=".claude/state/smoke.json"
if [ ! -f "$S" ]; then say SKIP smoke "no $S (run scripts/smoke-check.sh if this is a runnable app)"
else
  SO=$(json_get "$(cat "$S")" '.ok'); SU=$(json_get "$(cat "$S")" '.url'); SS=$(json_get "$(cat "$S")" '.status')
  if [ "$SO" = "true" ]; then say PASS smoke "ok ${SU:+$SU }status ${SS:-?}"
  else say FAIL smoke "smoke.json ok is not true (status ${SS:-?}) — see $S"; fi
fi

if [ "$INREPO" -eq 0 ]; then
  for n in secrets env-file leftovers lockfile clean-tree; do say SKIP "$n" "not a git repo"; done
else
  # 3. secrets in tracked files (high-confidence patterns only; never prints the match)
  HITS=""
  scan() {  # scan <label> <ere>
    local f
    f=$(git ls-files -z | xargs -0 grep -I -l -E -e "$2" -- 2>/dev/null | head -3 | tr '\n' ' ')
    [ -n "$f" ] && HITS="$HITS[$1: $f] "
  }
  scan "aws-key" 'AKIA[0-9A-Z]{16}'
  scan "github-token" 'ghp_[A-Za-z0-9]{36}'
  scan "anthropic-key" 'sk-ant-[A-Za-z0-9_-]{20,}'
  scan "private-key" '-----BEGIN (RSA |EC |OPENSSH |DSA |PGP )?PRIVATE KEY-----'
  if [ -n "$HITS" ]; then say FAIL secrets "$HITS"; else say PASS secrets "no high-confidence secret patterns in tracked files"; fi

  # 4. .env
  TRACKED_ENV=$(git ls-files | grep -E '(^|/)\.env($|\.[^/]*$)' | grep -v -E '\.(example|sample|template)$' | head -3 | tr '\n' ' ')
  if [ -n "$TRACKED_ENV" ]; then say FAIL env-file "tracked: $TRACKED_ENV"
  elif [ ! -f .gitignore ] || ! grep -q -E '^/?\.env(\*|\.\*)?/?$' .gitignore; then say WARN env-file ".env not tracked, but .gitignore does not cover it"
  else say PASS env-file ".env not tracked and ignored"; fi

  # 5. leftover debug markers in lines added vs default branch
  BASE=""
  for b in origin/HEAD origin/main origin/master main master; do
    git rev-parse --verify -q "$b" >/dev/null 2>&1 && { BASE=$(git merge-base "$b" HEAD 2>/dev/null); [ -n "$BASE" ] && break; }
  done
  [ -z "$BASE" ] && BASE=$(git rev-parse --verify -q HEAD 2>/dev/null)
  if [ -z "$BASE" ]; then say SKIP leftovers "no commits yet"
  else
    LEFT=$(git diff -U0 "$BASE" -- . ':!*.md' ':!*.lock' ':!package-lock.json' ':!*test*' ':!*spec*' ':!tests/*' 2>/dev/null | awk '
      /^\+\+\+ b\// {f=substr($0,7); next}
      /^\+\+\+ / {next}
      /^\+/ && /(TODO|FIXME|console\.log|debugger|print\()/ {print f ": " substr($0,2,80)}' | head -5)
    UNT=$(git ls-files --others --exclude-standard | grep -v -E '(\.md$|test|spec)' | head -50 | while IFS= read -r uf; do
      grep -H -E '(TODO|FIXME|console\.log|debugger|print\()' "$uf" 2>/dev/null | head -1; done | head -5)
    ALL=$(printf '%s\n%s' "$LEFT" "$UNT" | sed '/^$/d' | head -5)
    if [ -n "$ALL" ]; then say WARN leftovers "TODO/FIXME/console.log/debugger/print( in changed files:"; printf '%s\n' "$ALL" | sed 's/^/        /'
    else say PASS leftovers "none in files changed vs default branch"; fi
  fi

  # 6. lockfile present + committed
  MAN=""; LOCKS=""
  if [ -f package.json ]; then MAN=package.json; LOCKS="package-lock.json yarn.lock pnpm-lock.yaml bun.lockb bun.lock"
  elif [ -f Cargo.toml ]; then MAN=Cargo.toml; LOCKS="Cargo.lock"
  elif [ -f Gemfile ]; then MAN=Gemfile; LOCKS="Gemfile.lock"
  elif [ -f composer.json ]; then MAN=composer.json; LOCKS="composer.lock"
  elif [ -f pyproject.toml ]; then MAN=pyproject.toml; LOCKS="uv.lock poetry.lock pdm.lock Pipfile.lock requirements.txt"
  fi
  if [ -z "$MAN" ]; then say SKIP lockfile "no known dependency manifest"
  else
    FOUND=""; for l in $LOCKS; do [ -f "$l" ] && { FOUND="$l"; break; }; done
    if [ -z "$FOUND" ]; then say FAIL lockfile "$MAN present, no lockfile (${LOCKS%% *} ...)"
    elif [ -z "$(git ls-files -- "$FOUND")" ]; then say FAIL lockfile "$FOUND exists but is not committed"
    else say PASS lockfile "$FOUND committed"; fi
  fi

  # 13. working tree
  DIRTY=$(git status --porcelain 2>/dev/null | grep -v -E ' \.claude/' | head -3 | tr '\n' ';')
  if [ -n "$DIRTY" ]; then say WARN clean-tree "uncommitted changes: $DIRTY"; else say PASS clean-tree "working tree clean"; fi
fi

# 7. README
if ls README* >/dev/null 2>&1; then say PASS readme "$(ls README* | head -1)"; else say FAIL readme "no README"; fi

# 8. web project heuristics (WARN only)
WEB=0
[ -f index.html ] || [ -f public/index.html ] && WEB=1
[ -f package.json ] && grep -q -E '"(react|next|vue|svelte|express|fastify|koa|vite|nuxt)"' package.json && WEB=1
if [ "$WEB" -eq 0 ]; then
  say SKIP error-page "not detected as a web project"; say SKIP viewport "not detected as a web project"
else
  SRC=$(grep -r -l -I -E -i '404|not-found|notFound|error\.(html|tsx|jsx)|errorhandler|app\.use\(\(err' --include='*' \
    --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=.claude --exclude-dir=dist --exclude-dir=build . 2>/dev/null | head -1)
  if [ -n "$SRC" ]; then say PASS error-page "404/error handling mentioned in $SRC"
  else say WARN error-page "no 404/error-page handling found (heuristic)"; fi
  HT=$( { git ls-files 2>/dev/null; } | grep -E '(^|/)index\.html$' | grep -v node_modules | head -5)
  [ -z "$HT" ] && HT=$(ls index.html public/index.html 2>/dev/null)
  if [ -z "$HT" ]; then
    if grep -r -l -I -E 'viewport' app src 2>/dev/null | head -1 | grep -q .; then say PASS viewport "viewport configured in app/src"
    else say SKIP viewport "no HTML entrypoint found"; fi
  else
    MISSING=""; for h in $HT; do grep -q -i 'name=["'"'"']viewport["'"'"']' "$h" || MISSING="$MISSING$h "; done
    if [ -n "$MISSING" ]; then say WARN viewport "no <meta name=viewport> in: $MISSING"; else say PASS viewport "meta viewport present in HTML entrypoints"; fi
  fi
fi

# 12. TASKS.md
if [ ! -f TASKS.md ]; then say SKIP tasks "no TASKS.md"
else
  OPEN=$(grep -c -E '^[[:space:]]*[-*][[:space:]]+\[ \]' TASKS.md 2>/dev/null)
  if [ "${OPEN:-0}" -gt 0 ]; then say FAIL tasks "$OPEN open task(s) in TASKS.md"; else say PASS tasks "no open tasks"; fi
fi

echo "-- $NPASS pass, $NWARN warn, $NFAIL fail, $NSKIP skip. Report only: nothing was pushed or deployed. Push/deploy is a human decision."
[ "$STRICT" -eq 1 ] && [ "$NFAIL" -gt 0 ] && exit 1
exit 0
