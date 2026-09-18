#!/usr/bin/env bash
# PreToolUse — matcher: Edit|Write
# Scope creep, mechanically prevented. If TASKS.md declares which files the
# current task touches, editing anything else is blocked. The model doesn't
# get to decide that a drive-by refactor is in scope.
#
# How it reads TASKS.md: finds the first unchecked task line and pulls its
# "files:" field. Expected planner format:
#   - [ ] 3. Add retry logic — files: src/http.ts, src/config.ts — done when: ...
#
# Fails OPEN (allows the edit) when it can't determine scope, because a
# half-parsed task board must never wedge the whole session:
#   - no TASKS.md
#   - no unchecked tasks
#   - the current task has no "files:" field
#   - MOGGER_SCOPE_GUARD=off
source "$(dirname "$0")/lib.sh"

[ "${MOGGER_SCOPE_GUARD:-on}" = "off" ] && exit 0

INPUT=$(cat)
FILE=$(json_get "$INPUT" '.tool_input.file_path')
[ -z "$FILE" ] && exit 0
[ -f TASKS.md ] || exit 0

# First unchecked task line
TASK_LINE=$(grep -m1 '^\s*- \[ \]' TASKS.md 2>/dev/null)
[ -z "$TASK_LINE" ] && exit 0

# Extract the files: field — everything between "files:" and the next " — " or EOL
SCOPE=$(printf '%s' "$TASK_LINE" | sed -n 's/.*files:[[:space:]]*\([^—]*\).*/\1/p')
[ -z "$SCOPE" ] && exit 0   # task declares no scope — nothing to enforce

# Always-allowed paths: the kit's own bookkeeping and test scaffolding
case "$FILE" in
  *TASKS.md|*RUNS.md|*CONSTRAINTS.md|*STACK.md|*.claude/state/*) exit 0 ;;
esac

# Normalize the edited path for comparison (strip leading ./ and any absolute prefix of cwd)
CWD=$(pwd)
REL="${FILE#$CWD/}"
REL="${REL#./}"

# Does REL match any declared path? Declared entries are comma/space separated
# and may be a file, a directory prefix, or a glob.
MATCH=0
IFS=',' read -ra ENTRIES <<< "$SCOPE"
for e in "${ENTRIES[@]}"; do
  e="$(printf '%s' "$e" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s#^\./##')"
  [ -z "$e" ] && continue
  # exact, glob, or directory-prefix match
  if [ "$REL" = "$e" ] || [[ "$REL" == $e ]] || [[ "$REL" == "${e%/}/"* ]]; then
    MATCH=1; break
  fi
done

if [ "$MATCH" -eq 0 ]; then
  cat >&2 <<EOF
BLOCKED (scope): '$REL' is not in the current task's declared scope.
Task: $(printf '%s' "$TASK_LINE" | sed 's/^\s*- \[ \] //' | cut -c1-90)
Declared files: $(printf '%s' "$SCOPE" | sed 's/[[:space:]]*$//')

If this edit genuinely belongs to this task, add the path to that task's
"files:" list in TASKS.md first — that makes the scope change explicit and
reviewable. If it belongs to a different task, finish this one first. If
it's an unrelated improvement you noticed, note it in TASKS.md as a new
unchecked task instead of doing it now.
EOF
  exit 2
fi

exit 0
