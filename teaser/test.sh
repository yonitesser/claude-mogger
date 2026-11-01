#!/usr/bin/env bash
# Offline test, no Claude needed: feeds the hook the JSON Claude Code sends.
cd "$(dirname "$0")" || exit 1
export CLAUDE_PROJECT_DIR=$(mktemp -d)
H=hooks/scripts/secret-guard.sh; fail=0
t() { # name expected_exit file content
  local out rc
  out=$(jq -n --arg f "$3" --arg c "$4" '{tool_input:{file_path:$f,content:$c}}' | bash "$H" 2>&1); rc=$?
  if [ "$rc" = "$2" ]; then echo "ok   $1"; else echo "FAIL $1 (exit $rc, wanted $2) $out"; fail=1; fi
}
t "blocks AWS key"       2 config.py "AWS_KEY = \"AK""IAIOSFODNN7ABCDEFG\""
t "blocks GitHub token"  2 a.js "const t = 'gh""p_$(printf 'a%.0s' {1..36})'"
t "blocks .env write"    2 .env "X=1"
t "allows normal code"   0 app.py 'print("hello")'
t "allows env read"      0 app.py 'k = os.environ["API_KEY"]'
t "allows placeholder"   0 app.py 'API_KEY = "your-key-here-1234567890"'
t "allows .env.example"  0 .env.example "API_KEY=your-key-here"
exit $fail
