#!/usr/bin/env bash
# Fail-closed gates. Run: bash tests/failclosed.test.sh
# Claude Code 2.1.295+ blocks the action when a hook marked onFailure:"block"
# crashes, times out, or exits with anything but 0 or 2. So every gate must
# (a) carry that mark in hooks.json and (b) exit only 0 or 2 on odd input.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
GATES="require-approval require-approval-mcp danger-guard secret-guard-bash secret-read-guard config-guard secret-guard protect-pipeline-files"

echo "== hooks.json marks each gate onFailure:block"
for g in $GATES; do
  n=$(python3 - "$ROOT/hooks/hooks.json" "$g" <<'PY'
import json,sys
h=json.load(open(sys.argv[1]))['hooks']['PreToolUse']
hits=[x for grp in h for x in grp['hooks'] if x['command'].rstrip('"').endswith('/'+sys.argv[2]+'.sh')]
print(len(hits) if hits and all(x.get('onFailure')=='block' for x in hits) else 0)
PY
)
  [ "$n" -ge 1 ] && ok "$g has onFailure block" || bad "$g missing onFailure block"
done

echo "== gates exit only 0 or 2 on odd input"
SB=$(mktemp -d); trap 'rm -rf "$SB"' EXIT; cd "$SB"
for g in $GATES; do
  for in in '' 'not json' '{}' '{"tool_name":"Bash"}' '{"tool_name":"Bash","tool_input":{"command":123}}' '{"tool_name":"Edit","tool_input":{"file_path":null}}'; do
    printf '%s' "$in" | CLAUDE_PROJECT_DIR="$SB" bash "$ROOT/hooks/scripts/$g.sh" >/dev/null 2>&1; rc=$?
    case "$rc" in 0|2) ok "$g rc=$rc on '${in:0:24}'" ;; *) bad "$g rc=$rc on '${in:0:24}'" ;; esac
  done
done

echo "== timeouts: gates stay fast"
for g in $GATES; do
  s=$SECONDS; printf '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | CLAUDE_PROJECT_DIR="$SB" bash "$ROOT/hooks/scripts/$g.sh" >/dev/null 2>&1
  [ $((SECONDS-s)) -le 5 ] && ok "$g under 5s" || bad "$g slow"
done
echo "failclosed: $PASS passed, $FAIL failed"; [ "$FAIL" = 0 ]
