#!/usr/bin/env bash
# docs.sh — can someone else (or you in 3 months) run this project?
# REPORT-ONLY: never modifies the project. Always exits 0.
#
# Checks: README exists and covers what/install/run/test/env/deploy; commands
# the README tells you to run actually exist (npm scripts, make targets, file
# paths); env vars used in code vs documented; LICENSE; tests documented.
# Section detection is heading/keyword heuristics; the command and env checks
# are real fact checks and cite file:line.
#
# Usage (from project root):  bash scripts/checks/docs.sh [project-dir]
# Output: one line per finding  LEVEL|check-id|message   (PASS WARN FAIL SKIP)
set -u
ROOT="${1:-.}"
cd "$ROOT" 2>/dev/null || { printf 'SKIP|docs-readme|cannot cd to %s\n' "$ROOT"; exit 0; }
TMP=$(mktemp -d 2>/dev/null || mktemp -d -t mogger)
[ -n "$TMP" ] && [ -d "$TMP" ] || { printf 'SKIP|docs-readme|no temp dir available\n'; exit 0; }
trap 'rm -rf "$TMP"' EXIT

out() { printf '%s|%s|%s\n' "$1" "$2" "$3"; }

find . \( -name node_modules -o -name .git -o -name dist -o -name build -o -name venv -o -name .venv \
  -o -name __pycache__ -o -name .next -o -name coverage -o -name .claude -o -name target -o -name vendor \
  -o -name .cache \) -prune -o -type f -print 2>/dev/null | sed 's|^\./||' | head -8000 > "$TMP/all"
: > "$TMP/src"; : > "$TMP/pkgs"; : > "$TMP/tests"; : > "$TMP/examples"
while IFS= read -r f; do
  case "$f" in
    *.min.js|*.map|*package-lock.json) continue;;
  esac
  case "$f" in
    *.env.example|*.env.sample|*.env.template|*.env.dist|*example.env|*env.example|*.env.local.example) printf '%s\n' "$f" >> "$TMP/examples"; continue;;
  esac
  case "$f" in
    *package.json) printf '%s\n' "$f" >> "$TMP/pkgs";;
  esac
  case "$f" in
    */test/*|*/tests/*|*/__tests__/*|*/spec/*|test/*|tests/*|__tests__/*|spec/*|*.test.*|*.spec.*|*/test_*|test_*|*_test.py|*_test.go) printf '%s\n' "$f" >> "$TMP/tests";;
  esac
  case "$f" in
    *.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs|*.vue|*.svelte|*.astro|*.py|*.rb|*.php|*.go|*.java|*.kt|*.cs|*.rs|*.prisma|*.erb|*.ejs) printf '%s\n' "$f" >> "$TMP/src";;
  esac
done < "$TMP/all"

# ---- 1. README ------------------------------------------------------------
README=""
for f in README.md readme.md Readme.md README README.rst README.txt README.markdown; do
  [ -f "$f" ] && { README="$f"; break; }
done
if [ -z "$README" ]; then
  out FAIL docs-readme "no README at project root: nobody else can tell what this is or how to run it"
  for id in what install run test env deploy; do
    out SKIP "docs-readme-$id" "no README"
  done
else
  NLINES=$(wc -l < "$README" | tr -d ' ')
  out PASS docs-readme "$README exists ($NLINES lines)"
  tr '[:upper:]' '[:lower:]' < "$README" > "$TMP/readme.lc"
  # sec <id> <heading-ere> <keyword-ere> <label>  -> PASS/WARN
  sec() {
    local id="$1" hre="$2" kre="$3" label="$4" hl kl
    hl=$(grep -n -E "^#+[[:space:]].*($hre)" "$TMP/readme.lc" | head -1 | cut -d: -f1)
    if [ -n "$hl" ]; then out PASS "docs-readme-$id" "$README:$hl has a heading for $label"; return; fi
    kl=$(grep -n -E "$kre" "$TMP/readme.lc" | head -1 | cut -d: -f1)
    if [ -n "$kl" ]; then out PASS "docs-readme-$id" "$README:$kl mentions $label (keyword match, no dedicated heading)"; return; fi
    out WARN "docs-readme-$id" "$README has no $label section or keywords (heuristic)"
  }
  # what it is: a real paragraph near the top
  para=$(awk 'NR<=25 && !/^[[:space:]]*(#|[!<>`|=-]|\[)/ && length($0) >= 40 { print NR; exit }' "$README")
  if [ -n "$para" ]; then out PASS docs-readme-what "$README:$para has a description paragraph"
  elif grep -q -E '^#+[[:space:]].*(about|overview|what|description|introduction)' "$TMP/readme.lc"; then out PASS docs-readme-what "$README has an about/overview heading"
  else out WARN docs-readme-what "$README has no plain-language description of what the project is in its first 25 lines (heuristic)"; fi
  sec install 'install|setup|set up|getting started|quick ?start|requirements|prerequisites' 'npm install|yarn install|pnpm install|pip install|bundle install|composer install|poetry install|go mod|cargo build|brew install' "install/setup steps"
  sec run 'run|usage|start|development|launch' 'npm (run )?(start|dev)|yarn (start|dev)|flask run|uvicorn|python3? .*[.]py|docker (compose )?up|make run|cargo run|go run|rails s|node .*[.]js' "how to run it"
  if [ -s "$TMP/tests" ] || grep -q '"test"' package.json 2>/dev/null; then
    sec test 'test' 'npm (run )?test|yarn test|pnpm test|pytest|go test|cargo test|make test|rspec|jest|vitest' "how to run tests"
  else
    out SKIP docs-readme-test "no test files found, nothing to document"
  fi
  sec env 'env|environment|configuration|config|secret' '[.]env|api_key|environment variable' "environment variables/configuration"
  sec deploy 'deploy|hosting|production|publish|release' 'deploy|vercel|netlify|heroku|fly[.]io|render[.]com|railway|docker|github pages' "deployment"
fi

# ---- 2. README commands really exist ---------------------------------------
if [ -z "$README" ]; then
  out SKIP docs-commands "no README"
else
  # script names from every package.json (jq, python3, else awk fallback)
  : > "$TMP/scripts"
  while IFS= read -r pj; do
    if command -v jq >/dev/null 2>&1; then
      jq -r '.scripts // {} | keys[]' "$pj" 2>/dev/null >> "$TMP/scripts"
    else
      awk '/"scripts"[[:space:]]*:/ {s=1; next} s && /}/ {exit} s { if (match($0, /"[^"]+"[[:space:]]*:/)) { k=substr($0,RSTART+1,RLENGTH-1); sub(/".*/,"",k); print k } }' "$pj" >> "$TMP/scripts"
    fi
  done < "$TMP/pkgs"
  NPKG=$(wc -l < "$TMP/pkgs" | tr -d ' ')
  MK=""
  for f in Makefile makefile GNUmakefile; do [ -f "$f" ] && { MK="$f"; break; }; done
  CHECKED=0; BAD=0
  bad() { BAD=$((BAD+1)); out FAIL docs-commands "$1"; }
  have_script() { grep -q -x -F -e "$1" "$TMP/scripts"; }

  # npm/yarn/pnpm run X
  grep -n -o -E '(npm|yarn|pnpm|bun) run(-script)? [[:alnum:]:_-]+' "$README" 2>/dev/null > "$TMP/c1"
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    ln=${l%%:*}; cmd=${l#*:}; name=${cmd##* }
    CHECKED=$((CHECKED+1))
    if [ "$NPKG" -eq 0 ]; then bad "$README:$ln says '$cmd' but there is no package.json"
    elif ! have_script "$name"; then bad "$README:$ln says '$cmd' but package.json has no '$name' script (has: $(tr '\n' ' ' < "$TMP/scripts"))"; fi
  done < "$TMP/c1"
  # yarn/pnpm shorthand for common scripts
  grep -n -o -E '(yarn|pnpm) (dev|build|lint|serve|preview|format|typecheck|migrate|seed)([^[:alnum:]_:-]|$)' "$README" 2>/dev/null > "$TMP/c1b"
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    ln=${l%%:*}; cmd=${l#*:}; name=$(printf '%s' "$cmd" | awk '{print $2}' | sed 's/[^[:alnum:]_:-]*$//')
    CHECKED=$((CHECKED+1))
    if [ "$NPKG" -eq 0 ]; then bad "$README:$ln says '$cmd' but there is no package.json"
    elif ! have_script "$name"; then bad "$README:$ln says '$cmd' but package.json has no '$name' script"; fi
  done < "$TMP/c1b"
  # npm test / npm start (built-ins that need a script; start falls back to server.js)
  grep -n -o -E 'npm (test|start)([^[:alnum:]_:-]|$)' "$README" 2>/dev/null > "$TMP/c2"
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    ln=${l%%:*}; cmd=${l#*:}; name=$(printf '%s' "$cmd" | awk '{print $2}' | sed 's/[^[:alnum:]_:-]*$//')
    CHECKED=$((CHECKED+1))
    if [ "$NPKG" -eq 0 ]; then bad "$README:$ln says 'npm $name' but there is no package.json"
    elif have_script "$name"; then :
    elif [ "$name" = "start" ] && [ -f server.js ]; then :
    else bad "$README:$ln says 'npm $name' but package.json has no '$name' script"; fi
  done < "$TMP/c2"
  # make X
  grep -n -o -E '(^|[^[:alnum:]_-])make [[:alnum:]_.-]+' "$README" 2>/dev/null > "$TMP/c3"
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    ln=${l%%:*}; cmd=${l#*:}; name=${cmd##* }
    case "$name" in -*) continue;; esac
    CHECKED=$((CHECKED+1))
    if [ -z "$MK" ]; then bad "$README:$ln says 'make $name' but there is no Makefile"
    elif ! grep -q -E "^$name[[:space:]]*:" "$MK"; then bad "$README:$ln says 'make $name' but $MK has no '$name' target"; fi
  done < "$TMP/c3"
  # interpreter + file path
  grep -n -o -E '(python3?|node|tsx|ts-node|bash|sh|ruby|php) [[:alnum:]_./-]+[.](py|js|mjs|cjs|ts|sh|rb|php)' "$README" 2>/dev/null > "$TMP/c4"
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    ln=${l%%:*}; cmd=${l#*:}; path=${cmd##* }
    case "$path" in *'$'*|*'<'*|*'{'*|*'*'*|http*) continue;; esac
    CHECKED=$((CHECKED+1))
    [ -f "$path" ] || [ -f "${path#./}" ] || bad "$README:$ln says '$cmd' but $path does not exist"
  done < "$TMP/c4"
  # docker compose / docker build need their files
  if grep -q -E 'docker[- ]compose (up|build|run)' "$README"; then
    ln=$(grep -n -E 'docker[- ]compose (up|build|run)' "$README" | head -1 | cut -d: -f1)
    CHECKED=$((CHECKED+1))
    [ -f docker-compose.yml ] || [ -f docker-compose.yaml ] || [ -f compose.yml ] || [ -f compose.yaml ] || bad "$README:$ln says docker compose but there is no compose file"
  fi
  if grep -q -E 'docker build' "$README"; then
    ln=$(grep -n -E 'docker build' "$README" | head -1 | cut -d: -f1)
    CHECKED=$((CHECKED+1))
    [ -f Dockerfile ] || bad "$README:$ln says docker build but there is no Dockerfile"
  fi
  # env example file the README points at
  for ex in .env.example .env.sample .env.template; do
    ln=$(grep -n -F -e "$ex" "$README" | head -1 | cut -d: -f1)
    if [ -n "$ln" ]; then
      CHECKED=$((CHECKED+1))
      [ -f "$ex" ] || bad "$README:$ln refers to $ex but that file does not exist"
    fi
  done
  if [ "$BAD" -eq 0 ]; then
    if [ "$CHECKED" -gt 0 ]; then out PASS docs-commands "$CHECKED command/file reference(s) in $README checked, all exist"
    else out SKIP docs-commands "no runnable commands (npm run / make / python file / docker) found in $README"; fi
  fi
fi

# ---- 3. env var sync -------------------------------------------------------
# name extraction: everything after the last non-identifier char of the match
ID='[[:alpha:]_][[:alnum:]_]*'
: > "$TMP/used"
if [ -s "$TMP/src" ]; then
  tr '\n' '\0' < "$TMP/src" | xargs -0 grep -H -n -o -I -E -e "process[.]env[.]$ID" -e "process[.]env[[].$ID" \
    -e "import[.]meta[.]env[.]$ID" -e "environ[[].$ID" -e "(environ[.]get|getenv|env[.]fetch|Deno[.]env[.]get|os[.]Getenv|System[.]getenv|(^|[^[:alnum:]_.])env)[(].$ID" \
    -e "(^|[^[:alnum:]_])ENV[[].$ID" -e "ENV[.]fetch[(].$ID" -- 2>/dev/null |
    awk -F: '{ loc = $1 ":" $2; m = $3; sub(/.*[^[:alnum:]_]/, "", m); if (m != "") print m "|" loc }' > "$TMP/used"
  # destructuring: const { A, B } = process.env
  tr '\n' '\0' < "$TMP/src" | xargs -0 grep -H -n -I -E -e '[{][^}]*[}][[:space:]]*=[[:space:]]*(process|import[.]meta)[.]env' -- 2>/dev/null |
    while IFS= read -r l; do
      loc=$(printf '%s' "$l" | cut -d: -f1,2)
      body=$(printf '%s' "$l" | cut -d: -f3- | sed 's/^[^{]*{//; s/}.*$//')
      printf '%s\n' "$body" | tr ',' '\n' | sed 's/[[:space:]]//g; s/[:=].*//' | while IFS= read -r nm; do
        [ -n "$nm" ] && printf '%s|%s\n' "$nm" "$loc"
      done
    done >> "$TMP/used"
fi
# drop runtime/platform vars nobody documents
grep -v -E '^(NODE_ENV|CI|HOME|PATH|PWD|USER|SHELL|TERM|TMPDIR|LANG|TZ|HOSTNAME|PYTHONPATH|VERCEL|VERCEL_ENV|VERCEL_URL|NEXT_RUNTIME|MODE|BASE_URL|PROD|DEV|SSR|npm_package_version|DEBUG)\|' "$TMP/used" > "$TMP/used2" 2>/dev/null
cut -d'|' -f1 "$TMP/used2" | sort -u > "$TMP/usednames"

# documented: .env.example-style files (any depth) and the README
: > "$TMP/docnames"; : > "$TMP/docexloc"
while IFS= read -r ex; do
  [ -n "$ex" ] || continue
  grep -n -E '^[[:space:]]*#?[[:space:]]*(export[[:space:]]+)?[[:alpha:]_][[:alnum:]_]*=' "$ex" 2>/dev/null |
    awk -F: -v f="$ex" '{ n = $1; t = $0; sub(/^[0-9]+:/, "", t); sub(/^[[:space:]]*#?[[:space:]]*(export[[:space:]]+)?/, "", t); sub(/=.*/, "", t); print t "|" f ":" n }' >> "$TMP/docexloc"
done < "$TMP/examples"
cut -d'|' -f1 "$TMP/docexloc" | sort -u > "$TMP/exnames"
EXFILE=$(head -1 "$TMP/examples")
NUSED=$(wc -l < "$TMP/usednames" | tr -d ' ')
if [ "$NUSED" -eq 0 ] && [ ! -s "$TMP/exnames" ]; then
  out SKIP docs-env "no environment-variable reads found in code"
else
  NUNDOC=0
  while IFS= read -r v; do
    [ -n "$v" ] || continue
    if grep -q -x -F -e "$v" "$TMP/exnames"; then continue; fi
    if [ -n "$README" ] && grep -q -w -F -e "$v" "$README" 2>/dev/null; then continue; fi
    NUNDOC=$((NUNDOC+1))
    if [ "$NUNDOC" -le 15 ]; then
      loc=$(grep -E "^$v[|]" "$TMP/used2" | head -1 | cut -d'|' -f2)
      out FAIL docs-env "$v is read at $loc but is not in ${EXFILE:-any .env.example} or the README"
    fi
  done < "$TMP/usednames"
  [ "$NUNDOC" -gt 15 ] && out FAIL docs-env "... and $((NUNDOC-15)) more undocumented env vars"
  if [ "$NUNDOC" -eq 0 ] && [ "$NUSED" -gt 0 ]; then
    out PASS docs-env "all $NUSED env var(s) read by code are documented in ${EXFILE:-README}"
  fi
  # documented but unused
  grep -E '(Dockerfile|[.](ya?ml|toml|json|conf|cfg|ini|sh)$)' "$TMP/all" | grep -v -F -x -f "$TMP/examples" | head -400 > "$TMP/cfglist"
  in_config() {
    [ -s "$TMP/cfglist" ] || return 0
    tr '\n' '\0' < "$TMP/cfglist" | xargs -0 grep -l -w -F -e "$1" -- 2>/dev/null | head -1
  }
  NUNUSED=0
  while IFS= read -r v; do
    [ -n "$v" ] || continue
    grep -q -x -F -e "$v" "$TMP/usednames" && continue
    # used by config outside code (compose, Dockerfile, yml, toml, json)?
    other=$(in_config "$v")
    [ -n "$other" ] && continue
    NUNUSED=$((NUNUSED+1))
    if [ "$NUNUSED" -le 15 ]; then
      loc=$(grep -E "^$v[|]" "$TMP/docexloc" | head -1 | cut -d'|' -f2)
      out WARN docs-env-unused "$v documented at $loc but no code reads it (typo, stale, or read implicitly by a framework?)"
    fi
  done < "$TMP/exnames"
  if [ "$NUNUSED" -eq 0 ] && [ -s "$TMP/exnames" ]; then
    out PASS docs-env-unused "every var in ${EXFILE} is read by code or config"
  fi
  if [ ! -s "$TMP/exnames" ] && [ "$NUSED" -gt 0 ] && [ -z "$EXFILE" ]; then
    out WARN docs-env-example "code reads $NUSED env var(s) but there is no .env.example (or .env.sample) to copy from"
  fi
fi

# ---- 4. LICENSE ------------------------------------------------------------
LIC=""
for f in LICENSE LICENSE.md LICENSE.txt LICENCE LICENCE.md COPYING COPYING.md license license.md; do
  [ -f "$f" ] && { LIC="$f"; break; }
done
if [ -n "$LIC" ]; then out PASS docs-license "$LIC present"
else
  pl=$(grep -n '"license"' package.json 2>/dev/null | head -1 | cut -d: -f1)
  if [ -n "$pl" ]; then out WARN docs-license "no LICENSE file, only a license field at package.json:$pl (add the full text so others may legally use it)"
  else out WARN docs-license "no LICENSE file: without one, others have no permission to use or change this code (owner to choose; this tool does not pick a license)"; fi
fi

# ---- 5. tests documented ---------------------------------------------------
TESTRUN=""
tl=$(grep -n -E '"test"[[:space:]]*:' package.json 2>/dev/null | grep -v -i 'no test specified' | head -1 | cut -d: -f1)
[ -n "$tl" ] && TESTRUN="package.json:$tl (npm test)"
if [ -z "$TESTRUN" ]; then
  tf=$(head -1 "$TMP/tests")
  [ -n "$tf" ] && TESTRUN="$tf"
fi
if [ -z "$TESTRUN" ]; then
  out SKIP docs-tests "no tests found"
elif [ -z "$README" ]; then
  out WARN docs-tests "tests exist ($TESTRUN) but there is no README to say how to run them"
else
  rl=$(grep -n -E 'npm (run )?test|yarn test|pnpm test|bun test|pytest|python3? -m (pytest|unittest)|go test|cargo test|make (test|check)|rspec|bundle exec rake|bash tests?/|vitest|jest|phpunit' "$TMP/readme.lc" | head -1 | cut -d: -f1)
  if [ -n "$rl" ]; then out PASS docs-tests "tests exist ($TESTRUN) and $README:$rl says how to run them"
  else out WARN docs-tests "tests exist ($TESTRUN) but $README does not say how to run them"; fi
fi
exit 0
