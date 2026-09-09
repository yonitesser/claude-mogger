#!/usr/bin/env bash
# Stop — no matcher
# "Done means done." If TASKS.md still has unchecked items and the Lead is
# trying to end its turn without recording a blocker, send it back to work.
# The model doesn't get to decide it's finished; the task board does.
#
# Escape hatches (any one of these lets the turn end):
#   - no TASKS.md, or no open tasks
#   - a line in TASKS.md starting with "BLOCKED:" or a "## Open questions" section with content
#   - TASKS.md "## Status:" line says "paused" or "awaiting-approval"
#   - stop_hook_active is true (we already sent it back once this turn — don't loop)
source "$(dirname "$0")/lib.sh"

INPUT=$(cat)

# Prevent infinite loop: if this hook already fired for this stop, allow it.
ACTIVE=$(json_get "$INPUT" '.stop_hook_active')
[ "$ACTIVE" = "true" ] && exit 0

[ -f TASKS.md ] || exit 0

OPEN=$(grep -c '^\s*- \[ \]' TASKS.md 2>/dev/null); OPEN=${OPEN:-0}
[ "$OPEN" -eq 0 ] && exit 0

# Legitimate reasons to stop with open tasks
grep -qiE '^\s*BLOCKED:' TASKS.md && exit 0
grep -qiE '^## Status:\s*(paused|awaiting-approval|blocked)' TASKS.md && exit 0
if awk '/^## Open questions/{f=1;next} /^## /{f=0} f' TASKS.md | grep -qE '\S'; then
  exit 0
fi

NEXT=$(grep -m1 '^\s*- \[ \]' TASKS.md | sed 's/^\s*- \[ \] //')
cat >&2 <<EOF
NOT DONE: TASKS.md has $OPEN open task(s) and no blocker recorded. Next: "$NEXT"
Either continue the loop (builder → tester → reviewer) on that task, or — if you are actually stuck — add a line "BLOCKED: <specific reason>" to TASKS.md (or set "## Status: awaiting-approval" if everything is built and you're waiting on a human merge). Then stop. Do not end the turn with silently unfinished work.
EOF
exit 2
