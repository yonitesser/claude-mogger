#!/usr/bin/env bash
# PreToolUse — matcher: Edit|Write
# Keeps credentials out of files. Two checks:
#   1. Writing to .env or .env.<anything> is blocked (except .env.example,
#      .env.sample, .env.template). Secrets belong in the user's shell/secret
#      manager; the model should write the .example file and tell the human.
#   2. The content being written (Write: content, Edit: new_string) is scanned
#      for high-confidence secret patterns (see secret-patterns.sh).
#
# Fails OPEN when jq/python3 are missing (json_get returns empty).
# Escape hatch: MOGGER_SECRET_GUARD=off (e.g. a test fixture full of fake keys).
source "$(dirname "$0")/lib.sh"
source "$(dirname "$0")/secret-patterns.sh"

[ "${MOGGER_SECRET_GUARD:-on}" = "off" ] && exit 0

INPUT=$(cat)
FILE=$(json_get "$INPUT" '.tool_input.file_path')
[ -z "$FILE" ] && exit 0

BASE="${FILE##*/}"
case "$BASE" in
  .env.example|.env.sample|.env.template) ;;
  .env|.env.*)
    mogger_event block "blocked a write to secrets file $BASE"; echo "BLOCKED: '$BASE' is a secrets file — do not write it. Put placeholder keys in .env.example instead and tell the user which real values they need to set themselves. Never ask for or invent real credentials." >&2
    exit 2 ;;
esac

CONTENT=$(json_get "$INPUT" '.tool_input.content')
NEW=$(json_get "$INPUT" '.tool_input.new_string')
[ -z "$CONTENT$NEW" ] && exit 0

FOUND=$(printf '%s\n%s\n' "$CONTENT" "$NEW" | mogger_find_secret) && {
  mogger_event block "blocked a secret in $BASE"; echo "BLOCKED: this write to '$FILE' contains what looks like a hardcoded secret: $FOUND. Read it from the environment instead (process.env.X / os.environ['X']) and document the variable in .env.example. If it is a deliberate fake for a test fixture, build it at runtime or use an obvious placeholder like 'your-key-here'." >&2
  exit 2
}
exit 0
