#!/usr/bin/env bash
# Toggle file: .claude/mogger.json + hooks/guards.tsv + scripts/mogger-config.sh.
# Run: bash tests/config.test.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
H="$ROOT/hooks/scripts"; C="$ROOT/scripts/mogger-config.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
SB=$(mktemp -d); trap 'rm -rf "$SB"' EXIT
export CLAUDE_PROJECT_DIR="$SB"
unset MOGGER_DANGER_GUARD MOGGER_HINT
DANGER='{"tool_name":"Bash","tool_input":{"command":"git reset --hard"}}'

# every catalog row: env var is really read by a hook, kind and texts present
while IFS=$'\t' read -r n e kind onv dflt on_t off_t; do
  grep -q "$e" "$H"/*.sh || bad "$n: $e not read by any hook"
  case "$kind" in safety|standard|optin) ;; *) bad "$n: bad kind" ;; esac
  [ -n "$on_t" ] && [ -n "$off_t" ] || bad "$n: missing ON/OFF text"
done < <(grep -v '^#' "$ROOT/hooks/guards.tsv")
ok "catalog rows valid"

# default: blocked
echo "$DANGER" | bash "$H/danger-guard.sh" >/dev/null 2>&1; [ $? -eq 2 ] && ok "danger-guard blocks by default" || bad "default block"

# safety guard off needs confirm
bash "$C" set danger-guard off >/dev/null 2>&1; [ $? -eq 3 ] && ok "safety off refused without --confirm" || bad "no refusal"
[ ! -f "$SB/.claude/mogger.json" ] && ok "nothing written on refusal" || bad "file written on refusal"
bash "$C" set danger-guard off --confirm >/dev/null 2>&1 && ok "safety off with --confirm" || bad "confirm failed"
echo "$DANGER" | bash "$H/danger-guard.sh" >/dev/null 2>&1; [ $? -eq 0 ] && ok "file turns the hook off" || bad "hook still blocks"

# env var wins over the file
echo "$DANGER" | MOGGER_DANGER_GUARD=on bash "$H/danger-guard.sh" >/dev/null 2>&1; [ $? -eq 2 ] && ok "env var wins over file" || bad "env lost"
bash "$C" list | grep -q '^danger-guard | off (file)' && ok "list shows state and source" || bad "list state"
MOGGER_DANGER_GUARD=on bash "$C" list | grep -q '^danger-guard | on (env)' && ok "list shows env source" || bad "list env"

# on again, reset
bash "$C" set danger-guard on >/dev/null; echo "$DANGER" | bash "$H/danger-guard.sh" >/dev/null 2>&1; [ $? -eq 2 ] && ok "on restores block" || bad "on failed"
bash "$C" set danger-guard off --confirm >/dev/null; bash "$C" reset danger-guard >/dev/null
echo "$DANGER" | bash "$H/danger-guard.sh" >/dev/null 2>&1; [ $? -eq 2 ] && ok "reset restores default" || bad "reset failed"

# standard guard: no confirm needed
bash "$C" set hint-noisy-bash off >/dev/null 2>&1 && ok "standard guard flips freely" || bad "standard flip"

# awkward input: unknown name, bad value, broken file fails open
bash "$C" set nope off >/dev/null 2>&1; [ $? -eq 1 ] && ok "unknown guard rejected" || bad "unknown accepted"
bash "$C" set hint-noisy-bash maybe >/dev/null 2>&1; [ $? -eq 1 ] && ok "bad value rejected" || bad "bad value accepted"
printf '{not json' > "$SB/.claude/mogger.json"
echo "$DANGER" | bash "$H/danger-guard.sh" >/dev/null 2>&1; [ $? -eq 2 ] && ok "broken file fails open (guard stays on)" || bad "broken file"
printf '{"danger-guard":["off"],"unknown":"off"}' > "$SB/.claude/mogger.json"
echo "$DANGER" | bash "$H/danger-guard.sh" >/dev/null 2>&1; [ $? -eq 2 ] && ok "wrong value type ignored" || bad "wrong type"

# non-default value: claim-check on maps to proof
printf '{"claim-check":"on"}' > "$SB/.claude/mogger.json"
( source "$H/lib.sh"; [ -z "${MOGGER_CLAIM_CHECK:-}" ] || [ "$MOGGER_CLAIM_CHECK" = proof ] ) && ok "claim-check on maps to proof" || bad "claim-check map"
printf '{"smoke-gate":"on"}' > "$SB/.claude/mogger.json"
( source "$H/lib.sh"; [ "$MOGGER_REQUIRE_SMOKE" = on ] ) && ok "opt-in gate turns on" || bad "opt-in"

# voice: a short line at session start, a log event for the mod, exact block text
unset MOGGER_VOICE; rm -f "$SB/.claude/mogger.json" "$SB/.claude/state/mogger-events.log"
V=$(cd "$SB" && bash "$H/session-start.sh" 2>/dev/null)
echo "$V" | grep -q '^Voice: .*Not on my watch' && ok "voice on by default: session line printed" || bad "voice line missing"
echo "$V" | grep -q 'No jokes in warnings or errors' && ok "voice line keeps warnings exact" || bad "voice exactness rule missing"
grep -q "$(printf 'voice\ton')" "$SB/.claude/state/mogger-events.log" && ok "voice on is logged for the mod" || bad "voice on not logged"
printf '{"voice":"off"}' > "$SB/.claude/mogger.json"; rm -f "$SB/.claude/state/mogger-events.log"
V=$(cd "$SB" && bash "$H/session-start.sh" 2>/dev/null)
echo "$V" | grep -q '^Voice:' && bad "voice off still printed" || ok "voice off in mogger.json: no voice line"
grep -q "$(printf 'voice\toff')" "$SB/.claude/state/mogger-events.log" && ok "voice off is logged for the mod" || bad "voice off not logged"
rm -f "$SB/.claude/mogger.json"
V=$(cd "$SB" && MOGGER_VOICE=off bash "$H/session-start.sh" 2>/dev/null)
echo "$V" | grep -q '^Voice:' && bad "env off ignored" || ok "MOGGER_VOICE=off turns the voice off"
bash "$C" list | grep -q '^voice | on (default) | standard' && ok "voice listed as a standard toggle" || bad "voice not listed"
ERR=$(echo "$DANGER" | bash "$H/danger-guard.sh" 2>&1 >/dev/null)
echo "$ERR" | grep -q '^BLOCKED: ' && ! echo "$ERR" | grep -qi 'watch\|mogged' && ok "block reasons carry no catchphrase" || bad "block text changed"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"; [ "$FAIL" -eq 0 ]
