#!/usr/bin/env bash
# First-run preferences prompt: prefs-notice.sh shows once, never blocks, stays quiet where nobody can answer.
# Run: bash tests/prefs.test.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
H="$ROOT/hooks/scripts"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
SB=$(mktemp -d); trap 'rm -rf "$SB"' EXIT
export CLAUDE_PROJECT_DIR="$SB"
cd "$SB"
unset MOGGER_HEADLESS MOGGER_PREFS_PROMPT CLAUDE_CODE_ENTRYPOINT
# pn [stdin json]: prints the hook's output; exit code goes to $SB/rc
pn() { printf '%s' "${1:-{\}}" | bash "$H/prefs-notice.sh" 2>&1; echo "rc=$?" >"$SB/rc"; }
reset() { rm -rf "$SB/.claude"; }
SWITCHES=".claude/mogger"".json"   # the switch file, spelled in parts

O=$(pn); case "$O" in *"mogger first run"*"AskUserQuestion"*"mogger:config"*) ok "first load asks and names the skill" ;; *) bad "first load: $O" ;; esac
[ "$(cat "$SB/rc")" = "rc=0" ] && ok "exits 0" || bad "exit code"
[ -f .claude/state/prefs-shown ] && ok "marker written" || bad "no marker"
[ -z "$(pn)" ] && ok "second load is silent (no nag)" || bad "nagged twice"

reset; O=$(MOGGER_PREFS_PROMPT=off pn); [ -z "$O" ] && [ ! -f .claude/state/prefs-shown ] && ok "MOGGER_PREFS_PROMPT=off is silent" || bad "off ignored"
reset; O=$(CLAUDE_CODE_ENTRYPOINT=sdk-cli pn); [ -z "$O" ] && [ ! -f .claude/state/prefs-shown ] && ok "headless/SDK run: silent, no marker" || bad "SDK run prompted"
reset; O=$(MOGGER_HEADLESS=on pn); [ -z "$O" ] && ok "MOGGER_HEADLESS=on: silent" || bad "headless prompted"
for m in bypassPermissions dontAsk auto; do
  reset; O=$(pn "{\"permission_mode\":\"$m\"}"); [ -z "$O" ] && [ ! -f .claude/state/prefs-shown ] && ok "$m: silent, no marker" || bad "$m prompted"
done
reset; O=$(pn '{"permission_mode":"default"}'); [ -n "$O" ] && ok "default permission mode asks" || bad "default mode silent"

# awkward input: user already chose; unwritable state dir; garbage stdin
reset; mkdir -p .claude; echo '{"danger-guard":"ask"}' > "$SWITCHES"
O=$(pn); [ -z "$O" ] && ok "switch file exists: silent" || bad "prompted after a choice"
reset; mkdir -p .claude; : > .claude/state   # a file where the dir should be
O=$(pn); [ -z "$O" ] && [ "$(cat "$SB/rc")" = "rc=0" ] && ok "cannot write marker: silent, never blocks" || bad "state error leaked: $O"
reset; O=$(pn 'not json {'); [ -n "$O" ] && ok "garbage stdin still works" || bad "garbage stdin broke it"

# wired in hooks.json, with a timeout, and the opt-out is documented in the script
jq -e '[.hooks.SessionStart[].hooks[] | select(.command|test("prefs-notice.sh")) | .timeout] | length==1' "$ROOT/hooks/hooks.json" >/dev/null && ok "hook wired with a timeout" || bad "hook not wired"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"; [ "$FAIL" -eq 0 ]
