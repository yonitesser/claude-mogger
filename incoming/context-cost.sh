#!/usr/bin/env bash
# context-cost.sh — how much text does mogger put in front of the model?
# Report only. Makes no model calls. Tokens are an ESTIMATE (characters / 4).
#
#   always-on   skill + agent frontmatter (names, descriptions, tools). The
#               model sees these every turn (cached after the first turn).
#   session     what hooks/scripts/session-start.sh prints, on a fixture
#               project with TASKS/CONSTRAINTS/STACK/DECISIONS filled in
#               (or on the current dir with --here).
#   on-demand   skill bodies. Loaded only when a skill fires.
#
# Usage: bash scripts/context-cost.sh [--json] [--here]
# Env:   MOGGER_ROOT   plugin root (default: parent of this script)
#
# Why it exists: a kit that claims to cut cost must show its own overhead.
# tests/context-budget.test.sh fails when the always-on part grows.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="${MOGGER_ROOT:-$(cd "$HERE/.." && pwd)}"
JSON=0; USE_HERE=0
for a in "$@"; do
  case "$a" in --json) JSON=1 ;; --here) USE_HERE=1 ;; esac
done

count() { wc -c | tr -d ' '; }
front() {  # print only the frontmatter block of a markdown file
  awk 'BEGIN{fm=0} /^---$/{fm++; next} fm==1' "$1"
}

SK=0; SKN=0
for f in "$ROOT"/skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  n=$(front "$f" | count); SK=$((SK + n)); SKN=$((SKN + 1))
done
AG=0; AGN=0
for f in "$ROOT"/agents/*.md; do
  [ -f "$f" ] || continue
  n=$(front "$f" | count); AG=$((AG + n)); AGN=$((AGN + 1))
done
ALWAYS=$((SK + AG))

BODY=0; BIG=""; BIGN=0
for f in "$ROOT"/skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  total=$(wc -c < "$f" | tr -d ' ')
  fm=$(front "$f" | count)
  b=$((total - fm)); BODY=$((BODY + b))
  if [ "$b" -gt "$BIGN" ]; then BIGN=$b; BIG=$(basename "$(dirname "$f")"); fi
done

# session-start output
SESSION=0
if [ "$USE_HERE" -eq 1 ]; then
  SESSION=$(bash "$ROOT/hooks/scripts/session-start.sh" </dev/null 2>/dev/null | count)
else
  T=$(mktemp -d 2>/dev/null || mktemp -d -t mogctx)
  ( cd "$T" && git init -q . 2>/dev/null
    printf '## Corrections\n- Never edit generated files.\n- Use pnpm, not npm.\n' > CONSTRAINTS.md
    printf '| Job | Library |\n|---|---|\n| HTTP | fetch |\n| Tests | vitest |\n' > STACK.md
    printf -- '- [x] 1. setup\n- [ ] 2. add login — files: src/a.ts — done when: test passes\n- [ ] 3. add logout\n' > TASKS.md
    i=1; : > DECISIONS.md
    while [ "$i" -le 12 ]; do
      printf '## #%s — decision %s\n- Why: reason %s\n- Status: active\n\n' "$i" "$i" "$i" >> DECISIONS.md; i=$((i + 1))
    done
    mkdir -p .claude/state
    printf '# Handoff\n- goal: demo\n- done: 1\n- next: 2\n' > .claude/state/handoff.md
    CLAUDE_PROJECT_DIR="$T" bash "$ROOT/hooks/scripts/session-start.sh" </dev/null 2>/dev/null | wc -c | tr -d ' ' > "$T/.size"
  )
  SESSION=$(cat "$T/.size" 2>/dev/null || echo 0)
  rm -rf "$T"
fi

tok() { echo $(( ($1 + 3) / 4 )); }
if [ "$JSON" -eq 1 ]; then
  printf '{"estimate":true,"chars_per_token":4,"always_on_chars":%s,"always_on_tokens":%s,"skills":%s,"agents":%s,"session_start_chars":%s,"session_start_tokens":%s,"on_demand_chars":%s,"biggest_skill":"%s","biggest_skill_chars":%s}\n' \
    "$ALWAYS" "$(tok $ALWAYS)" "$SKN" "$AGN" "$SESSION" "$(tok $SESSION)" "$BODY" "$BIG" "$BIGN"
else
  echo "mogger context cost (ESTIMATE: characters / 4; no model calls made)"
  printf '  always-on   %6s chars  ~%5s tokens  (%s skill + %s agent descriptions, every turn, cached)\n' "$ALWAYS" "$(tok $ALWAYS)" "$SKN" "$AGN"
  printf '  session     %6s chars  ~%5s tokens  (printed once at session start)\n' "$SESSION" "$(tok $SESSION)"
  printf '  on-demand   %6s chars  ~%5s tokens  (all skill bodies; only the ones that fire are loaded)\n' "$BODY" "$(tok $BODY)"
  printf '  biggest on-demand skill: %s (%s chars, ~%s tokens)\n' "$BIG" "$BIGN" "$(tok $BIGN)"
fi
exit 0
