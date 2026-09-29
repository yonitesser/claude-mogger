#!/usr/bin/env bash
# SessionStart — no matcher
# Whatever this prints to stdout is added to Claude's context at session
# start. So the Lead doesn't have to be *asked* to read CONSTRAINTS.md —
# it's already there. Enforced, not requested.
source "$(dirname "$0")/lib.sh"

# Dependency check — the other hooks need jq, or a REAL python3 (not the
# Windows Store stub, which sits on PATH but only prints an install nag).
if ! command -v jq >/dev/null 2>&1; then
  if ! command -v python3 >/dev/null 2>&1 || ! python3 -c '1' >/dev/null 2>&1; then
    echo "⚠ mogger: no working jq or python3 found. The approval-gate hooks will FAIL OPEN (not block anything) until one is installed. On Windows, 'python3' on PATH is often the Microsoft Store stub — install jq instead: winget install jqlang.jq"
    echo
  fi
fi

if [ -f CONSTRAINTS.md ]; then
  echo "## CONSTRAINTS.md (loaded automatically — every line is a hard rule)"
  # Skip the template preamble; print only the actual corrections
  awk '/^## Corrections/{f=1;next} f' CONSTRAINTS.md | grep -v '^<!--' | grep -v '^-->' | sed '/^$/d'
  echo
fi

if [ -f STACK.md ]; then
  echo "## STACK.md (library choices for this project — check before adding any dependency)"
  # Print only filled-in table rows and the "deliberately not used" section
  grep -E '^\|' STACK.md | grep -vE '^\|\s*(Job|---)' | grep -vE '^\|[^|]*\|\s*\|' 
  awk '/^## Deliberately NOT used/{f=1;next} /^## /{f=0} f' STACK.md | sed '/^$/d' | grep -v '^Things that were'
  echo
fi

if [ -f TASKS.md ]; then
  OPEN=$(grep -c '^\s*- \[ \]' TASKS.md 2>/dev/null); OPEN=${OPEN:-0}
  DONE=$(grep -c '^\s*- \[x\]' TASKS.md 2>/dev/null); DONE=${DONE:-0}
  echo "## TASKS.md status: $DONE done, $OPEN open"
  if [ "$OPEN" -gt 0 ]; then
    echo "Next open task:"
    grep -m1 '^\s*- \[ \]' TASKS.md
  fi
  echo
fi

echo "mogger active: git push/merge-to-protected/deploy/money are hook-blocked. Haiku reads, Sonnet builds, you orchestrate. Don't Read or Grep yourself — use explorer/bulk-reader."
exit 0
