#!/usr/bin/env bash
set -euo pipefail
src="${0%/*}"
dst="${CLAUDE_PROJECT_DIR:-$PWD}/.claude/mogger-skill"
mkdir -p "$dst"
cp -R "$src/hooks" "$src/scripts" "$dst/"
chmod +x "$dst"/hooks/scripts/*.sh "$dst"/scripts/*.sh 2>/dev/null || true
echo "mogger guards installed in $dst"
