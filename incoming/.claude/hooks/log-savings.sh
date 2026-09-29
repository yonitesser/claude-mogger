#!/usr/bin/env bash
# Called by an agent at the end of its own turn, not a lifecycle hook.
# Self-reported, not verified — same trust level as the agent's own prose,
# unlike the hard-gated hooks. Documented as such everywhere this shows up.
#
# Usage: log-savings.sh <agent> <model> <input_chars> <output_chars>
set -euo pipefail
AGENT="${1:?agent name required}"
MODEL="${2:?model required}"
IN_CHARS="${3:-0}"
OUT_CHARS="${4:-0}"

STATE_DIR=".claude/state"
mkdir -p "$STATE_DIR"
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")

printf '{"ts":"%s","agent":"%s","model":"%s","input_chars":%s,"output_chars":%s}\n' \
  "$TS" "$AGENT" "$MODEL" "$IN_CHARS" "$OUT_CHARS" >> "$STATE_DIR/savings.jsonl"
