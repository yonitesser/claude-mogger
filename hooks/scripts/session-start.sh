#!/usr/bin/env bash
# SessionStart — no matcher
# Whatever this prints to stdout is added to Claude's context at session
# start. So the Lead doesn't have to be *asked* to read CONSTRAINTS.md —
# it's already there. Enforced, not requested.
source "${0%/*}/lib.sh"
# A new session starts untainted (see taint-mark.sh). A compact or resume keeps the same conversation,
# and the same untrusted text, so the taint stays.
IFS= read -r -t 1 -d '' SS_INPUT 2>/dev/null
case "$(json_get "${SS_INPUT:-}" '.source')" in compact|resume) ;; *) rm -f "${CLAUDE_PROJECT_DIR:-.}/.claude/state/tainted" 2>/dev/null ;; esac

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

# Active decisions (DECISIONS.md) — so settled choices are not re-argued
if [ -f DECISIONS.md ]; then
  source "${0%/*}/decisions-context.sh"
  DEC=$(decisions_context DECISIONS.md)
  if [ -n "$DEC" ]; then
    echo "## Active decisions (DECISIONS.md — cite before proposing anything that contradicts one)"
    echo "$DEC"
    echo
  fi
fi

# Handoff saved before the last compaction (facts only, see precompact-save.sh)
if [ -f "${0%/*}/handoff-context.sh" ]; then
  source "${0%/*}/handoff-context.sh"
  HND=$(handoff_context)
  if [ -n "$HND" ]; then
    echo "## Handoff (saved automatically before context was compacted)"
    echo "$HND"
    echo
  fi
fi

# Budget warning written by cost-cap.sh (estimate from transcript token counts)
if [ -f .claude/state/cost.json ] && command -v python3 >/dev/null 2>&1 && python3 -c '1' >/dev/null 2>&1; then
  python3 -c '
import json
try:
    w = json.load(open(".claude/state/cost.json")).get("warning")
    if w: print("⚠ mogger budget: " + str(w)); print()
except Exception:
    pass
' 2>/dev/null
fi

# One-time evals nudge + consented background auto-run (see evals-nudge.sh)
if [ -f "${0%/*}/evals-nudge.sh" ]; then
  source "${0%/*}/evals-nudge.sh"
  EV=$(evals_session_context 2>/dev/null)
  [ -n "$EV" ] && printf '%s\n\n' "$EV"
fi

source "${0%/*}/claim-lib.sh"; claim_baseline
echo "Least code, never least tests: skip it, reuse the repo (grep first), then stdlib, new code last. Every behaviour change gets a test (keep old test names). Do what was asked; if you disagree, do it and say so. Before \"done\": show output proving each ask, plus one awkward input. Cite file:line for code claims; mark unchecked ones UNVERIFIED:."

mogger_event info "mogger is on for this session"
# Voice (toggle: voice in .claude/mogger.json, MOGGER_VOICE=off). Few words on purpose: this line is paid for every session.
if [ "${MOGGER_VOICE:-on}" != "off" ]; then
  mogger_event voice on
  echo "Voice: smug, dry, clever, never mean. One fresh quip when a task ends or a guard blocks; never repeat one. No quips in warnings, errors or block reasons; clarity first."
else
  mogger_event voice off
fi
echo "mogger: push, merge-to-protected, deploy, money are hook-blocked. Read small files directly."
exit 0
