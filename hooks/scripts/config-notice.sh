#!/usr/bin/env bash
# SessionStart — no matcher. Stdout goes to Claude's context (and the human).
# A cloned repo can ship its own Claude hooks, MCP servers and settings, and they
# run with your permissions (see the Claude Code CVEs on exactly this). This keeps
# a fingerprint of the project's Claude config and says so when it is new or changed:
#   .claude/settings.json, .mcp.json, .claude/hooks/*  (settings.local.json is yours, not the repo's)
# First sight of a repo that HAS such files: lists them once. Later: only on change.
# Names and counts only, never file contents. Always exits 0. MOGGER_CONFIG_NOTICE=off disables.
source "$(dirname "$0")/lib.sh"
[ "${MOGGER_CONFIG_NOTICE:-on}" = "off" ] && exit 0
ROOT="${CLAUDE_PROJECT_DIR:-.}"
cd "$ROOT" 2>/dev/null || exit 0
FILES=""
for f in .claude/settings.json .mcp.json; do [ -f "$f" ] && FILES="$FILES $f"; done
if [ -d .claude/hooks ]; then
  H=$(find .claude/hooks -type f 2>/dev/null | LC_ALL=C sort); FILES="$FILES $H"
fi
FILES=$(printf '%s' "$FILES" | tr ' ' '\n' | sed '/^$/d')
STATE=.claude/state/config.sha
HASHER="sha256sum"; command -v sha256sum >/dev/null 2>&1 || HASHER="shasum -a 256"
NOW=""
if [ -n "$FILES" ]; then
  NOW=$(printf '%s\n' "$FILES" | while IFS= read -r f; do $HASHER "$f" 2>/dev/null; done)
fi
THEN=""; [ -f "$STATE" ] && THEN=$(cat "$STATE" 2>/dev/null)
save() { mkdir -p .claude/state 2>/dev/null && printf '%s\n' "$NOW" > "$STATE" 2>/dev/null; }

if [ -z "$NOW" ]; then
  [ -n "$THEN" ] && save   # config was removed: just record it
  exit 0
fi
[ "$NOW" = "$THEN" ] && exit 0

if [ ! -f "$STATE" ]; then
  echo "⚠ mogger: this project ships Claude config that runs with your permissions:"
  printf '%s\n' "$FILES" | sed 's/^/  - /'
  echo "  Read it before trusting this repo (hooks run shell commands; .mcp.json starts servers). Shown once."
else
  CHANGED=$(diff <(printf '%s\n' "$THEN") <(printf '%s\n' "$NOW") 2>/dev/null | sed -n 's/^> [0-9a-f]*  *//p')
  echo "⚠ mogger: the project's Claude config changed since the last session:"
  printf '%s\n' "${CHANGED:-$FILES}" | sed 's/^/  - /'
  echo "  If you did not change these, check git log / git diff for them before continuing."
fi
echo
save
exit 0
