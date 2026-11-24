#!/usr/bin/env bash
# PreToolUse hook — matches: Edit|Write|MultiEdit
# Lockfiles (package-lock.json, yarn.lock, poetry.lock, Cargo.lock...) are written by the
# package manager, with checksums and download URLs. A model that edits one by hand can
# break the install or slip in a different source. Install through the package manager.
# States (MOGGER_LOCKFILE_GUARD): ask (default) = permission prompt for the human; on = block;
# off = allow. Where no prompt can be shown, ask blocks. Files under test/fixture dirs pass.
# Pure bash; text matching only. A seat belt, not a sandbox. Fails open on bad input.

source "${0%/*}/lib.sh"
STATE=$(mogger_state MOGGER_LOCKFILE_GUARD ask)
[ "$STATE" = "off" ] && exit 0

INPUT=$(cat)
FILE=$(json_get "$INPUT" '.tool_input.file_path')
[ -z "$FILE" ] && exit 0
BASE=${FILE##*/}
case "$BASE" in
  package-lock.json|npm-shrinkwrap.json|yarn.lock|pnpm-lock.yaml|bun.lock|bun.lockb|poetry.lock|Pipfile.lock|uv.lock|pdm.lock|Cargo.lock|Gemfile.lock|composer.lock|go.sum|packages.lock.json|gradle.lockfile) ;;
  *) exit 0 ;;
esac
case "/$FILE" in */test/*|*/tests/*|*/__tests__/*|*/fixtures/*|*/fixture/*|*/testdata/*|*/examples/*) exit 0 ;; esac

WHY="$BASE is written by the package manager (checksums, download URLs). Change dependencies with the package manager (npm install, poetry add, cargo add...), not by hand."
if [ "$STATE" = ask ] && mogger_can_ask "$INPUT"; then
  mogger_event warn "asked before a hand edit of $BASE"
  mogger_ask_json "$WHY Approve only if you asked for this edit."
  exit 0
fi
mogger_event block "blocked a hand edit of $BASE"
echo "BLOCKED: $WHY Ask the human, or set MOGGER_LOCKFILE_GUARD=off." >&2
exit 2
