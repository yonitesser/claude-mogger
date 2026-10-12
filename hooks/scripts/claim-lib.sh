#!/usr/bin/env bash
# Sourced by stop-claim-check.sh and session-start.sh: fingerprint of non-doc files changed in the work tree.
FPF=".claude/state/claim-check.fp"
fingerprint() {
  if git rev-parse --git-dir >/dev/null 2>&1; then
    { git status --porcelain -uall 2>/dev/null | grep -viE '\.(md|txt|rst|json|ya?ml|toml|lock|csv)$|\.claude/|^\?\? .*(__pycache__|\.pyc)' ; git diff HEAD -- . ':!*.md' ':!.claude' 2>/dev/null; } | cksum
  else
    find . -type f -not -path './.git/*' -not -path './.claude/*' -not -path '*/__pycache__/*' -not -name '*.pyc' \
      -not -regex '.*\.\(md\|txt\|rst\|json\|ya?ml\|toml\|lock\|csv\)' -exec cksum {} + 2>/dev/null | sort | cksum
  fi
}
claim_baseline() { mkdir -p .claude/state 2>/dev/null; fingerprint > "$FPF" 2>/dev/null; }
