#!/usr/bin/env bash
# Tests for smoke-check.sh, require-smoke-pass.sh, ship-check.sh.
# Run: bash tests/run-check.test.sh   (no external network; local servers only)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
H="$ROOT/hooks/scripts"; SC="$ROOT/scripts/smoke-check.sh"; SHIP="$ROOT/scripts/ship-check.sh"
PASS=0; FAIL=0
BASE=$(mktemp -d)
cleanup() { rm -rf "$BASE"; }
trap cleanup EXIT

t() {  # t <description> <command...>  — passes when the command succeeds
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); printf '  ok   %s\n' "$desc"
  else FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$desc"; fi
}
eq() { [ "$1" = "$2" ]; }
has() { grep -q -- "$2" "$1"; }      # has <file> <text>
hasnt() { ! grep -q -- "$2" "$1"; }
free_port() { python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])'; }
port_closed() { ! curl -s -o /dev/null --max-time 1 "http://127.0.0.1:$1/" 2>/dev/null; }

if ! command -v python3 >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  echo "SKIP: python3 and curl required"; exit 0
fi

newproj() { rm -rf "$BASE/p"; mkdir -p "$BASE/p"; cd "$BASE/p"; }

echo "== smoke-check.sh: passing server"
newproj; P=$(free_port)
MOGGER_RUN_CMD="python3 -m http.server $P --bind 127.0.0.1" MOGGER_SMOKE_URL="http://127.0.0.1:$P" MOGGER_SMOKE_TIMEOUT=15 bash "$SC" >out.txt 2>&1; RC=$?
t "exit 0 on healthy server" eq "$RC" 0
if [ "$RC" -ne 0 ]; then echo "--- DIAG out.txt"; cat out.txt; echo "--- DIAG smoke.log"; cat .claude/state/smoke.log 2>&1 | head -20; echo "--- DIAG smoke.json"; cat .claude/state/smoke.json; echo "--- DIAG python3: $(command -v python3) $(python3 -V 2>&1)"; env | grep -i proxy
  echo "--- DIAG matrix"; sw_ver=$(sw_vers -productVersion 2>&1); echo "macos $sw_ver"; ls /usr/bin/python3 2>&1
  try() { # try <label> <cmd using $DP>
    DP=$(free_port); bash -c "$2" >dl.txt 2>&1 & TP=$!; sleep 3
    echo "diag[$1] code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://127.0.0.1:$DP/" 2>&1) $(head -c 150 dl.txt | tr '\n' ' ')"; kill $TP 2>/dev/null; pkill -f "$DP" 2>/dev/null; }
  DP0=0
  try homebrew-py 'python3 -m http.server $DP --bind 127.0.0.1'
  try homebrew-py-nobind 'python3 -m http.server $DP'
  try homebrew-py-localhost 'python3 -m http.server $DP --bind localhost'
  [ -x /usr/bin/python3 ] && try system-py '/usr/bin/python3 -m http.server $DP --bind 127.0.0.1'
  command -v node >/dev/null && try node "node -e \"require('http').createServer((q,r)=>r.end('ok')).listen($(free_port),'127.0.0.1')\"" 
  command -v ruby >/dev/null && try ruby 'ruby -run -e httpd . -p $DP -b 127.0.0.1'
  try nc 'while true; do printf "HTTP/1.0 200 OK\r\n\r\nok" | nc -l 127.0.0.1 $DP; done'
  echo "--- DIAG pf"; sudo -n pfctl -s rules 2>&1 | head -5; /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>&1 | head -2

fi
t "smoke.json ok:true" has .claude/state/smoke.json '"ok":true'
t "smoke.json has url" has .claude/state/smoke.json "127.0.0.1:$P"
t "smoke.json status 200" has .claude/state/smoke.json '"status":"200"'
t "smoke.json has ts and cmd" has .claude/state/smoke.json '"ts":"20'
t "smoke.json has errors[] empty" has .claude/state/smoke.json '"errors":\[\]'
t "listener killed after exit" port_closed "$P"
t "no orphan http.server process" bash -c "! pgrep -f '[h]ttp.server $P' >/dev/null"

echo "== smoke-check.sh: port parsed from output"
newproj; P=$(free_port)
MOGGER_RUN_CMD="echo 'ready on http://localhost:$P'; exec python3 -m http.server $P --bind 127.0.0.1" MOGGER_SMOKE_TIMEOUT=15 bash "$SC" >out.txt 2>&1; RC=$?
t "exit 0 with url discovered from log" eq "$RC" 0
t "discovered url recorded" has .claude/state/smoke.json "localhost:$P"
t "discovered-port listener cleaned up" port_closed "$P"

echo "== smoke-check.sh: server never starts"
newproj; P=$(free_port)
MOGGER_RUN_CMD="sleep 7000$$" MOGGER_SMOKE_URL="http://127.0.0.1:$P" MOGGER_SMOKE_TIMEOUT=2 bash "$SC" >out.txt 2>&1; RC=$?
t "exit 1 on timeout" eq "$RC" 1
t "smoke.json ok:false" has .claude/state/smoke.json '"ok":false'
t "timeout error recorded" has .claude/state/smoke.json 'within 2s'
t "hung process killed" bash -c "! pgrep -f '[s]leep 7000$$' >/dev/null"

echo "== smoke-check.sh: crash with Traceback"
newproj; P=$(free_port)
MOGGER_RUN_CMD="python3 -c \"raise RuntimeError('boom-marker')\"" MOGGER_SMOKE_URL="http://127.0.0.1:$P" MOGGER_SMOKE_TIMEOUT=10 bash "$SC" >out.txt 2>&1; RC=$?
t "exit 1 on crash" eq "$RC" 1
t "Traceback captured in errors" has .claude/state/smoke.json 'Traceback'
t "exact error line captured" has .claude/state/smoke.json 'boom-marker'
t "early exit reported" has .claude/state/smoke.json 'exited early'

echo "== smoke-check.sh: healthy but logs errors"
newproj; P=$(free_port)
MOGGER_RUN_CMD="echo 'Error: db unreachable' >&2; exec python3 -m http.server $P --bind 127.0.0.1" MOGGER_SMOKE_URL="http://127.0.0.1:$P" MOGGER_SMOKE_TIMEOUT=15 bash "$SC" >out.txt 2>&1; RC=$?
t "exit 1 when 200 but Error: in output" eq "$RC" 1
t "error line recorded" has .claude/state/smoke.json 'db unreachable'
t "listener cleaned up after error case" port_closed "$P"

echo "== smoke-check.sh: MOGGER_SMOKE_CMD"
newproj
MOGGER_SMOKE_CMD="true" bash "$SC" >out.txt 2>&1; RC=$?
t "cmd success exits 0" eq "$RC" 0
t "cmd success ok:true" has .claude/state/smoke.json '"ok":true'
MOGGER_SMOKE_CMD="echo cli-broke; exit 3" bash "$SC" >out.txt 2>&1; RC=$?
t "cmd failure exits 1" eq "$RC" 1
t "cmd failure records exit code" has .claude/state/smoke.json '"status":"exit 3"'
t "cmd failure records output" has .claude/state/smoke.json 'cli-broke'

echo "== smoke-check.sh: config + detection"
newproj
bash "$SC" >out.txt 2>&1; RC=$?
t "no command detected exits 1" eq "$RC" 1
t "no-command reason recorded" has .claude/state/smoke.json 'no start command'
newproj; mkdir -p .claude; printf '{"smoke_cmd":"true"}' > .claude/mogger.json
if command -v jq >/dev/null 2>&1 || python3 -c 1 >/dev/null 2>&1; then
  bash "$SC" >out.txt 2>&1; t "smoke_cmd read from .claude/mogger.json" eq "$?" 0
fi
newproj; printf -- '- run: `echo hi; exit 5`\n' > STACK.md
# STACK.md run: line is picked up as the server command (fails fast, proving it was read)
MOGGER_SMOKE_TIMEOUT=5 bash "$SC" >out.txt 2>&1
t "STACK.md run: line used as start command" has .claude/state/smoke.json 'exit 5'
newproj; printf '{"scripts":{"dev":"echo dev-script; exit 1"}}' > package.json
MOGGER_SMOKE_TIMEOUT=5 bash "$SC" >out.txt 2>&1
t "package.json dev script autodetected" has .claude/state/smoke.json 'npm run dev'
newproj
MOGGER_SMOKE_CMD=true MOGGER_SMOKE_SCREENSHOT=on bash "$SC" >out.txt 2>&1
t "screenshot flag never breaks a cmd-mode run" eq "$?" 0

echo "== require-smoke-pass.sh"
newproj; mkdir -p .claude/state
task() { printf '{"tool_name":"Task","tool_input":{"subagent_type":"%s"}}' "$1"; }
hook() { task "$1" | env "${@:2}" bash "$H/require-smoke-pass.sh" >/dev/null 2>&1; echo $?; }
t "opt-out (default): no marker, reviewer allowed" eq "$(hook reviewer)" 0
t "opted in: no marker blocks reviewer" eq "$(hook reviewer MOGGER_REQUIRE_SMOKE=on)" 2
t "opted in: non-reviewer allowed" eq "$(hook builder MOGGER_REQUIRE_SMOKE=on)" 0
echo '{"ok":false,"errors":["x"]}' > .claude/state/smoke.json
t "opted in: ok:false blocks" eq "$(hook reviewer MOGGER_REQUIRE_SMOKE=on)" 2
echo '{"ok":true,"errors":[]}' > .claude/state/smoke.json
touch -t 202001010000 src.txt
t "opted in: ok:true + fresh allows" eq "$(hook reviewer MOGGER_REQUIRE_SMOKE=on)" 0
echo change > newer.txt
t "opted in: source newer than smoke.json blocks (stale)" eq "$(hook reviewer MOGGER_REQUIRE_SMOKE=on)" 2
rm newer.txt
t "GATE_ALL_TASKS gates unknown agent" eq "$(hook mystery MOGGER_REQUIRE_SMOKE=on MOGGER_GATE_ALL_TASKS=on)" 0
rm .claude/state/smoke.json
t "GATE_ALL_TASKS blocks unknown agent w/o marker" eq "$(hook mystery MOGGER_REQUIRE_SMOKE=on MOGGER_GATE_ALL_TASKS=on)" 2
t "GATE_ALL_TASKS exempts verifier" eq "$(hook verifier MOGGER_REQUIRE_SMOKE=on MOGGER_GATE_ALL_TASKS=on)" 0

echo "== ship-check.sh"
mkfix() {  # a clean, shippable fake repo
  rm -rf "$BASE/r"; mkdir -p "$BASE/r"; cd "$BASE/r"
  git init -q -b main . 2>/dev/null || { git init -q .; git checkout -q -b main; }
  printf '# app\n' > README.md
  printf '{"name":"a","dependencies":{"express":"4"}}' > package.json
  printf '{}' > package-lock.json
  printf '.env\nnode_modules/\n.claude/state/\n' > .gitignore
  printf '<html><head><meta name="viewport" content="width=device-width"></head><body>ok</body></html>' > index.html
  printf 'app.use((req,res)=>res.status(404).send("nf"))\n' > server.js
  printf -- '- [x] one\n' > TASKS.md
  git add -A; git -c user.name=t -c user.email=t@t commit -q -m init
  mkdir -p .claude/state
  echo '{"status":"pass","exit_code":0,"scope":"full"}' > .claude/state/last_test_result.json
  echo '{"ok":true,"url":"http://x","status":"200","errors":[]}' > .claude/state/smoke.json
}
ship() { bash "$SHIP" "$@" > "$BASE/ship.out" 2>&1; echo $?; }
mkfix
t "clean repo: exit 0" eq "$(ship)" 0
t "clean repo: strict exit 0" eq "$(ship --strict)" 0
t "clean repo: no FAIL lines" hasnt "$BASE/ship.out" '^FAIL'
t "clean repo: tests PASS" has "$BASE/ship.out" '^PASS  *tests'
t "clean repo: says never pushes" has "$BASE/ship.out" 'nothing was pushed or deployed'

mkfix; printf 'k=%s%s\n' "AKI" "AABCDEFGHIJKLMNOP" > cfg.txt; git add -A; git -c user.name=t -c user.email=t@t commit -q -m s
t "secret: FAIL reported" eq "$(ship)" 0
t "secret: FAIL line present" has "$BASE/ship.out" '^FAIL  *secrets'
t "secret: value not echoed" hasnt "$BASE/ship.out" 'ABCDEFGHIJKLMNOP'
t "secret: --strict exits 1" eq "$(ship --strict)" 1
mkfix; printf '%s\n' "-----BEGIN RSA PRIVATE KEY-----" > k.pem; git add -A; git -c user.name=t -c user.email=t@t commit -q -m k; ship >/dev/null
t "private key block detected" has "$BASE/ship.out" '^FAIL  *secrets'

mkfix; echo 'X=1' > .env; git add -f .env; git -c user.name=t -c user.email=t@t commit -q -m e; ship >/dev/null
t ".env tracked: FAIL" has "$BASE/ship.out" '^FAIL  *env-file'
mkfix; printf 'node_modules/\n' > .gitignore; git add -A; git -c user.name=t -c user.email=t@t commit -q -m g; ship >/dev/null
t ".gitignore missing .env: WARN" has "$BASE/ship.out" '^WARN  *env-file'

mkfix; git rm -q package-lock.json; git -c user.name=t -c user.email=t@t commit -q -m nl; ship >/dev/null
t "missing lockfile: FAIL" has "$BASE/ship.out" '^FAIL  *lockfile'
mkfix; git rm -q README.md; git -c user.name=t -c user.email=t@t commit -q -m nr; ship >/dev/null
t "missing README: FAIL" has "$BASE/ship.out" '^FAIL  *readme'
mkfix; printf -- '- [ ] open\n' > TASKS.md; git add -A; git -c user.name=t -c user.email=t@t commit -q -m t; ship >/dev/null
t "open task: FAIL" has "$BASE/ship.out" '^FAIL  *tasks'

mkfix; rm .claude/state/last_test_result.json; ship >/dev/null
t "no test marker: FAIL" has "$BASE/ship.out" '^FAIL  *tests'
mkfix; echo '{"status":"pass","scope":"affected"}' > .claude/state/last_test_result.json; ship >/dev/null
t "affected-only pass: FAIL" has "$BASE/ship.out" '^FAIL  *tests'
mkfix; echo '{"status":"fail","scope":"full"}' > .claude/state/last_test_result.json; ship >/dev/null
t "failed test marker: FAIL" has "$BASE/ship.out" '^FAIL  *tests'
mkfix; touch -t 202001010000 .claude/state/last_test_result.json; ship >/dev/null
t "stale test marker: FAIL" has "$BASE/ship.out" 'stale'

mkfix; echo '{"ok":false,"status":"000"}' > .claude/state/smoke.json; ship >/dev/null
t "smoke ok:false: FAIL" has "$BASE/ship.out" '^FAIL  *smoke'
mkfix; rm .claude/state/smoke.json; ship >/dev/null
t "no smoke.json: SKIP" has "$BASE/ship.out" '^SKIP  *smoke'

mkfix; git checkout -q -b feat; echo 'console.log("dbg")' >> server.js; git -c user.name=t -c user.email=t@t commit -qam dbg; ship >/dev/null
t "console.log in changed file: WARN" has "$BASE/ship.out" '^WARN  *leftovers'
mkfix; git checkout -q -b feat; echo '// TODO later' >> server.js; git -c user.name=t -c user.email=t@t commit -qam td; ship >/dev/null
t "TODO added on branch: WARN" has "$BASE/ship.out" 'TODO later'
mkfix; echo 'x' >> server.js; ship >/dev/null
t "dirty tree: WARN" has "$BASE/ship.out" '^WARN  *clean-tree'
mkfix; printf '<html><body>hi</body></html>' > index.html; git add -A; git -c user.name=t -c user.email=t@t commit -q -m v; ship >/dev/null
t "missing viewport meta: WARN" has "$BASE/ship.out" '^WARN  *viewport'
mkfix; printf 'app.get("/",(q,r)=>r.send("x"))\n' > server.js; git add -A; git -c user.name=t -c user.email=t@t commit -q -m ne; ship >/dev/null
t "no 404 handling: WARN" has "$BASE/ship.out" '^WARN  *error-page'
mkfix; ship --strict >/dev/null; t "ship-check leaves repo untouched" bash -c "[ -z \"\$(git status --porcelain | grep -v '.claude/')\" ]"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
