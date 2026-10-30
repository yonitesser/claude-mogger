#!/usr/bin/env bash
# deploy.sh - deploy-habit checks for ship-check. REPORT-ONLY.
#
# Looks for the habits that keep a live site recoverable: version control
# with a remote, .gitignore, CI that runs tests, a staging/preview copy,
# push/PR-based deploys instead of editing the live server, a committed
# lockfile, a documented start command, migrations in the deploy path, a
# rollback path, a backup mention and a health-check endpoint.
# Most of these are heuristics (text search); each message names the
# evidence or says what was not found. It never deploys, pushes or writes.
#
# Contract (shared by scripts/checks/*.sh): one line per finding,
#   LEVEL|check-id|message      LEVEL = PASS | WARN | FAIL | SKIP
# Always exits 0. Run from the project root.
set -u

say() {  # say <LEVEL> <check-id> <message>  (message kept to one line)
  local m
  m=$(printf '%s' "$3" | tr '\n\r|' '   ')
  printf '%s|%s|%s\n' "$1" "$2" "$m"
}

# Files worth reading (skips dependency/build dirs). Depth-limited.
find_files() {  # find_files <name-test...>
  find . -maxdepth 4 \( -name node_modules -o -name .git -o -name dist -o -name build \
    -o -name venv -o -name .venv -o -name target -o -name .claude -o -name vendor \
    -o -name __pycache__ -o -name .next \) -prune -o -type f \( "$@" \) -print 2>/dev/null \
    | sed 's|^\./||' | head -400
}
gfile() {  # gfile <ere> <newline-separated file list> -> first file that matches
  [ -n "$2" ] || return 0
  printf '%s\n' "$2" | tr '\n' '\0' | xargs -0 grep -I -l -i -E -e "$1" /dev/null 2>/dev/null | head -1
}

DOCS=$(find_files -name '*.md' -o -name '*.txt' -o -name '*.rst' -o -name '*.yml' -o -name '*.yaml' \
  -o -name '*.toml' -o -name 'Dockerfile*' -o -name 'Procfile' -o -name 'Makefile' -o -name 'package.json' \
  -o -name 'vercel.json' -o -name '*.sh' | grep -v -i -E '(^|/)(CHANGELOG|LICENSE|CONSTRAINTS|CURATION|CONSIDERED)' )
CI=""
for f in .github/workflows/*.yml .github/workflows/*.yaml .gitlab-ci.yml .circleci/config.yml \
         azure-pipelines.yml bitbucket-pipelines.yml Jenkinsfile .travis.yml .drone.yml; do
  [ -f "$f" ] && CI="$CI$f
"
done
CI=$(printf '%s' "$CI" | sed '/^$/d')
DEPLOYF="$CI"
for f in Dockerfile* Procfile Makefile package.json docker-compose*.yml docker-compose*.yaml *.toml README*; do
  [ -f "$f" ] && DEPLOYF="$DEPLOYF
$f"
done
DEPLOYF=$(printf '%s' "$DEPLOYF" | sed '/^$/d')

INREPO=0; git rev-parse --is-inside-work-tree >/dev/null 2>&1 && INREPO=1

# 1. version control + remote
if [ "$INREPO" -eq 0 ]; then
  say FAIL deploy-git "not a git repository: no history, nothing can be rolled back. Run git init and commit"
else
  REM=$(git remote 2>/dev/null | head -1)
  if [ -z "$REM" ]; then say WARN deploy-git "git repo has no remote: the only copy is on this machine"
  else say PASS deploy-git "git repo with remote '$REM'"; fi
fi

# 2. .gitignore coverage
if [ ! -f .gitignore ]; then
  say WARN deploy-gitignore "no .gitignore: .env, dependencies and build output can get committed"
else
  MISS=""
  grep -q -E '^/?\.env(\*|\.\*)?/?$' .gitignore || MISS="$MISS .env"
  if [ -f package.json ] || [ -d node_modules ]; then grep -q -E '^/?node_modules/?\*?$' .gitignore || MISS="$MISS node_modules"; fi
  if [ -d dist ] || [ -d build ] || { [ -f package.json ] && grep -q -E '"build"[[:space:]]*:' package.json; }; then
    grep -q -E '^/?(dist|build)/?\*?$' .gitignore || MISS="$MISS dist/build"
  fi
  if [ -n "$MISS" ]; then say WARN deploy-gitignore ".gitignore does not cover:$MISS"
  else say PASS deploy-gitignore ".gitignore covers .env and the dependency/build dirs this project has"; fi
fi

# 3. CI present, and does it run tests
if [ -z "$CI" ]; then
  say WARN deploy-ci "no CI config (.github/workflows, .gitlab-ci.yml, ...): nothing checks a change before it ships"
  say SKIP deploy-ci-tests "no CI config"
else
  say PASS deploy-ci "CI config: $(printf '%s' "$CI" | head -1)"
  T=$(gfile 'npm (run )?test|npm t([[:space:]]|$)|yarn (run )?test|pnpm (run )?test|pytest|go test|cargo test|rspec|phpunit|mvn (-B )?test|gradle test|vitest|jest|make test|bash tests/|tests/.*\.sh' "$CI")
  if [ -n "$T" ]; then say PASS deploy-ci-tests "CI runs tests ($T)"
  else say WARN deploy-ci-tests "CI config found but no test command in it: $(printf '%s' "$CI" | head -1)"; fi
fi

# 4. second environment
SN=$(find_files -iname '*staging*' -o -iname '*preview*' | head -1)
SG=$(gfile 'staging|preview|pre-?prod|deploy-preview|branch-deploy' "$DOCS")
if [ -n "$SN" ]; then say PASS deploy-staging "staging/preview config file: $SN"
elif [ -n "$SG" ]; then say PASS deploy-staging "staging/preview mentioned in $SG"
else say WARN deploy-staging "no staging or preview environment mentioned (heuristic): changes may go straight to the live site"; fi

# 5. deploy flow: push/PR vs direct edits
DIRECT=$(gfile '(scp|sftp|ftp|rsync)[[:space:]]+[^#]*[@:]|filezilla|cpanel|edit(ing)? (files )?(directly )?on the server|upload(ed)? (via|with|by) ftp' "$DOCS")
GITDEP=""
for f in vercel.json netlify.toml render.yaml fly.toml app.json .vercel; do [ -e "$f" ] && GITDEP="$f"; done
[ -z "$GITDEP" ] && GITDEP=$(gfile 'deploy' "$CI")
[ -z "$GITDEP" ] && GITDEP=$(gfile 'git push (heroku|dokku)|deploys? (on|when|after) (a )?(push|merge|pull request)|merge to main|pull request' "$DOCS")
if [ -n "$DIRECT" ]; then say WARN deploy-flow "copies files straight to a server (scp/rsync/ftp) in $DIRECT (heuristic): prefer push/PR-triggered deploys"
elif [ -n "$GITDEP" ]; then say PASS deploy-flow "git/CI-driven deploy evidence in $GITDEP (heuristic)"
else say WARN deploy-flow "no evidence the deploy goes through push/PR (heuristic): how does a change reach the live site?"; fi

# 6. lockfile
MAN=""; LOCKS=""
if [ -f package.json ]; then MAN=package.json; LOCKS="package-lock.json yarn.lock pnpm-lock.yaml bun.lockb bun.lock"
elif [ -f Cargo.toml ]; then MAN=Cargo.toml; LOCKS="Cargo.lock"
elif [ -f Gemfile ]; then MAN=Gemfile; LOCKS="Gemfile.lock"
elif [ -f composer.json ]; then MAN=composer.json; LOCKS="composer.lock"
elif [ -f pyproject.toml ]; then MAN=pyproject.toml; LOCKS="uv.lock poetry.lock pdm.lock Pipfile.lock requirements.txt"
elif [ -f requirements.txt ]; then MAN=requirements.txt; LOCKS="requirements.txt"
fi
if [ -z "$MAN" ]; then say SKIP deploy-lockfile "no known dependency manifest"
else
  FOUND=""; for l in $LOCKS; do [ -f "$l" ] && { FOUND="$l"; break; }; done
  if [ -z "$FOUND" ]; then say WARN deploy-lockfile "$MAN present but no lockfile: the live site may install different versions than you tested"
  elif [ "$INREPO" -eq 1 ] && [ -z "$(git ls-files -- "$FOUND" 2>/dev/null)" ]; then say WARN deploy-lockfile "$FOUND exists but is not committed"
  elif [ "$INREPO" -eq 1 ]; then say PASS deploy-lockfile "$FOUND present and tracked by git"
  else say PASS deploy-lockfile "$FOUND present"; fi
fi

# 7. Dockerfile / start command
SERVER=0
{ [ -f package.json ] && grep -q -E '"(express|fastify|koa|next|nuxt|hapi|nest|@nestjs/core)"' package.json; } && SERVER=1
[ -f Procfile ] && SERVER=1
ls Dockerfile* >/dev/null 2>&1 && grep -q -i '^EXPOSE' Dockerfile* 2>/dev/null && SERVER=1
{ [ -f requirements.txt ] && grep -q -i -E '^(flask|fastapi|django|uvicorn|gunicorn)' requirements.txt; } && SERVER=1
if ls Dockerfile* >/dev/null 2>&1; then
  DF=$(ls Dockerfile* | head -1)
  if grep -q -i -E '^(CMD|ENTRYPOINT)' "$DF"; then say PASS deploy-runcmd "$DF defines CMD/ENTRYPOINT"
  else say WARN deploy-runcmd "$DF has no CMD or ENTRYPOINT"; fi
elif [ -f Procfile ]; then say PASS deploy-runcmd "Procfile defines the process"
elif [ -f package.json ] && grep -q -E '"start"[[:space:]]*:' package.json; then say PASS deploy-runcmd "package.json has a start script"
elif [ -n "$(gfile 'npm (run )?(start|dev)|uvicorn|gunicorn|flask run|python3? [^ ]*(app|main|server|manage)\.py|docker (compose|run)|make (run|start)|cargo run|go run' "$(ls README* 2>/dev/null)")" ]; then
  say PASS deploy-runcmd "start command documented in README"
elif [ -z "$MAN" ]; then say SKIP deploy-runcmd "no manifest or server detected (static site or library?)"
else say WARN deploy-runcmd "no Dockerfile, Procfile, start script or README run command: nobody else can start it"; fi

# 8. migrations in the deploy path
MIG=""
for d in prisma/migrations migrations db/migrate alembic drizzle knex; do [ -d "$d" ] && MIG="$d"; done
[ -z "$MIG" ] && [ -f manage.py ] && MIG="manage.py"
if [ -z "$MIG" ]; then say SKIP deploy-migrations "no migrations directory or tool found"
else
  MF=$(gfile 'migrate|migration|prisma (migrate|db push)|alembic upgrade|flyway|db:migrate' "$DEPLOYF")
  if [ -n "$MF" ]; then say PASS deploy-migrations "migrations ($MIG) run or documented in $MF (heuristic)"
  else say WARN deploy-migrations "$MIG exists but no deploy file mentions running migrations (heuristic)"; fi
fi

# 9. rollback path
RB=$(gfile 'rollback|roll back|roll-back|revert|previous (version|release|deploy)|redeploy (the )?(last|previous)|git reset' "$DOCS")
if [ -n "$RB" ]; then say PASS deploy-rollback "rollback/revert mentioned in $RB"
else say WARN deploy-rollback "no mention of rollback, revert or previous version: how do you undo a bad release?"; fi

# 10. backups (database detail lives in database.sh)
BK=$(gfile 'backup|back up|back-up|restore|snapshot|pg_dump|mysqldump|litestream' "$DOCS")
if [ -n "$BK" ]; then say PASS deploy-backup "backup/restore mentioned in $BK"
else say WARN deploy-backup "no backup or restore mention in README, docs or CI"; fi

# 11. health check
if [ "$SERVER" -eq 0 ]; then say SKIP deploy-health "no server detected"
else
  CODE=$(find_files -name '*.js' -o -name '*.mjs' -o -name '*.ts' -o -name '*.py' -o -name '*.go' -o -name '*.rb' -o -name '*.php')
  HC=$(gfile 'health(check|z)?|readyz|livez|/ping' "$DOCS
$CODE")
  if [ -n "$HC" ]; then say PASS deploy-health "health check mentioned in $HC"
  else say WARN deploy-health "server detected but no health-check endpoint mentioned (/health, /healthz)"; fi
fi
exit 0
