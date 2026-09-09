#!/usr/bin/env bash
# PostToolUse hook — matches: Edit|Write
# Runs the project's OWN formatter/linter on the file Claude just touched.
# Detects which tool the project uses by its config files — never installs
# anything, never imposes a formatter the project didn't already choose.
# If nothing is configured, does nothing. Clean code as a hook, not a hope.

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[ -z "$FILE" ] || [ ! -f "$FILE" ] && exit 0

EXT="${FILE##*.}"
has() { command -v "$1" >/dev/null 2>&1; }
cfg() { for f in "$@"; do [ -f "$f" ] && return 0; done; return 1; }

case "$EXT" in
  js|jsx|ts|tsx|mjs|cjs|json|css|scss|md|yaml|yml)
    if cfg biome.json biome.jsonc && has biome; then
      biome format --write "$FILE" >/dev/null 2>&1
      biome lint --write "$FILE" >/dev/null 2>&1
    elif cfg .prettierrc .prettierrc.json .prettierrc.js .prettierrc.cjs prettier.config.js prettier.config.mjs .prettierrc.yaml .prettierrc.yml && has npx; then
      npx --no-install prettier --write "$FILE" >/dev/null 2>&1
    fi
    if [[ "$EXT" =~ ^(js|jsx|ts|tsx|mjs|cjs)$ ]] && cfg eslint.config.js eslint.config.mjs eslint.config.cjs .eslintrc .eslintrc.js .eslintrc.cjs .eslintrc.json && has npx; then
      npx --no-install eslint --fix "$FILE" >/dev/null 2>&1
    fi
    ;;
  py)
    if cfg ruff.toml .ruff.toml || grep -q '\[tool.ruff' pyproject.toml 2>/dev/null; then
      has ruff && { ruff format "$FILE" >/dev/null 2>&1; ruff check --fix "$FILE" >/dev/null 2>&1; }
    elif grep -q '\[tool.black' pyproject.toml 2>/dev/null && has black; then
      black -q "$FILE" >/dev/null 2>&1
    fi
    ;;
  go)
    has gofmt && gofmt -w "$FILE" >/dev/null 2>&1
    has goimports && goimports -w "$FILE" >/dev/null 2>&1
    ;;
  rs)
    has rustfmt && rustfmt --edition 2021 "$FILE" >/dev/null 2>&1
    ;;
  rb)
    cfg .rubocop.yml && has rubocop && rubocop -a "$FILE" >/dev/null 2>&1
    ;;
  php)
    cfg .php-cs-fixer.php .php-cs-fixer.dist.php && has php-cs-fixer && php-cs-fixer fix "$FILE" >/dev/null 2>&1
    ;;
  sh|bash)
    has shfmt && shfmt -w "$FILE" >/dev/null 2>&1
    ;;
esac

# Always exit 0 — a formatter failure should never block Claude's edit.
# Formatting is a nicety layered on top; correctness gating is the
# tester's job, not this hook's.
exit 0
