#!/usr/bin/env bash
# smoke-check.sh — "does it actually run?" Tests passing != app works.
#
# Starts the project's app in the background, polls a URL until HTTP 2xx/3xx
# (or timeout), scans the captured output for error signatures, ALWAYS kills
# the whole process tree on exit, and records the result in
# .claude/state/smoke.json  {ok,url,status,seconds,errors[],cmd,ts}.
# Exit 0 = ok, 1 = not ok. REPORT-ONLY: this NEVER pushes, deploys or touches
# anything outside the project dir + .claude/state/. The push/deploy gate
# stays human.
#
# Run it from the project root:  bash scripts/smoke-check.sh
#
# Config (first hit wins):
#   MOGGER_SMOKE_CMD     a command that must exit 0 (CLI/library, no server)
#   MOGGER_RUN_CMD       server start command;   MOGGER_SMOKE_URL  URL to poll
#   .claude/mogger.json  {"run": "...", "url": "...", "smoke_cmd": "..."}
#   STACK.md / .claude/STACK.md  lines `run: <cmd>` and `url: <url>`
#   autodetect: package.json scripts dev|start, Makefile `run:`,
#               uvicorn/flask/django hints
# Other env:
#   MOGGER_SMOKE_TIMEOUT   seconds (default 30)
#   MOGGER_SMOKE_SCREENSHOT=on   also try scripts/smoke-browser.mjs (Playwright);
#                                skipped with a note when unavailable.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
[ -f "$HERE/../hooks/scripts/lib.sh" ] && source "$HERE/../hooks/scripts/lib.sh"
type json_get >/dev/null 2>&1 || json_get() { printf ''; }

STATE=".claude/state"
OUT="$STATE/smoke.json"
LOG="$STATE/smoke.log"
TIMEOUT="${MOGGER_SMOKE_TIMEOUT:-30}"
case "$TIMEOUT" in ''|*[!0-9]*) TIMEOUT=30 ;; esac
mkdir -p "$STATE" 2>/dev/null
: > "$LOG"

PID=""
NOTES=""
BROWSER_ERRS=""

# ---- process-tree cleanup -------------------------------------------------
descendants() {  # post-order list of all descendant pids of $1
  local c
  for c in $(ps -A -o pid=,ppid= 2>/dev/null | awk -v P="$1" '$2==P{print $1}'); do
    descendants "$c"; echo "$c"
  done
}
kill_tree() {
  [ -z "$PID" ] && return 0
  local all p
  all="$(descendants "$PID") $PID"
  for p in $all; do kill -TERM "$p" 2>/dev/null; done
  sleep 0.3
  for p in $all; do kill -0 "$p" 2>/dev/null && kill -KILL "$p" 2>/dev/null; done
  wait "$PID" 2>/dev/null
  PID=""
}
trap 'kill_tree' EXIT
trap 'kill_tree; exit 1' INT TERM

# ---- json helpers ---------------------------------------------------------
jesc() { tr -d '\000-\010\013-\037' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/	/ /g' | cut -c1-300; }
json_array() {  # stdin lines -> ["a","b"]
  local first=1 line out="["
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    [ $first -eq 0 ] && out="$out,"
    out="$out\"$(printf '%s' "$line" | jesc)\""; first=0
  done
  printf '%s]' "$out"
}
write_result() {  # ok url status cmd errors_text
  local ok="$1" url="$2" status="$3" cmd="$4" errs="$5" ts errj notej
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  errj=$(printf '%s\n' "$errs" | json_array)
  notej=$(printf '%s\n' "$NOTES" | json_array)
  local bj; bj=$(printf '%s\n' "$BROWSER_ERRS" | json_array)
  printf '{"ok":%s,"url":"%s","status":"%s","seconds":%s,"errors":%s,"cmd":"%s","ts":"%s","notes":%s,"browser_errors":%s}\n' \
    "$ok" "$(printf '%s' "$url" | jesc)" "$status" "$SECONDS" "$errj" \
    "$(printf '%s' "$cmd" | jesc)" "$ts" "$notej" "$bj" > "$OUT"
}
scan_errors() {  # error-signature lines from the log
  grep -E -i 'Traceback \(most recent|Error:|Cannot find module|EADDRINUSE|unhandled( promise)? rejection|UnhandledPromiseRejection|HTTP/[0-9.]+"? 500|status[ =:]+500|" 500 |500 Internal Server Error|command not found|No such file or directory' "$LOG" 2>/dev/null | head -10
}

# ---- config resolution ----------------------------------------------------
CFG=""; [ -f .claude/mogger.json ] && CFG="$(cat .claude/mogger.json)"
stack_line() {  # stack_line <key>
  local f
  for f in STACK.md .claude/STACK.md; do
    [ -f "$f" ] && { sed -n "s/^[[:space:]]*[-*]*[[:space:]]*\`\{0,1\}$1\`\{0,1\}:[[:space:]]*\`\{0,1\}\(.*[^\`[:space:]]\)\`\{0,1\}[[:space:]]*$/\1/p" "$f" | head -1; return; }
  done
}

CHECK_CMD="${MOGGER_SMOKE_CMD:-}"
[ -z "$CHECK_CMD" ] && [ -n "$CFG" ] && CHECK_CMD="$(json_get "$CFG" '.smoke_cmd')"
RUN_CMD="${MOGGER_RUN_CMD:-}"
URL="${MOGGER_SMOKE_URL:-}"
if [ -z "$CHECK_CMD" ]; then
  [ -z "$RUN_CMD" ] && [ -n "$CFG" ] && RUN_CMD="$(json_get "$CFG" '.run')"
  [ -z "$URL" ] && [ -n "$CFG" ] && URL="$(json_get "$CFG" '.url')"
  [ -z "$RUN_CMD" ] && RUN_CMD="$(stack_line run)"
  [ -z "$URL" ] && URL="$(stack_line url)"
fi
DEFAULT_URL="http://localhost:3000"
if [ -z "$CHECK_CMD" ] && [ -z "$RUN_CMD" ]; then
  if [ -f package.json ]; then
    if grep -q '"dev"[[:space:]]*:' package.json; then RUN_CMD="npm run dev"
    elif grep -q '"start"[[:space:]]*:' package.json; then RUN_CMD="npm start"; fi
  fi
  if [ -z "$RUN_CMD" ] && [ -f Makefile ] && grep -q '^run:' Makefile; then RUN_CMD="make run"; fi
  if [ -z "$RUN_CMD" ]; then
    if [ -f manage.py ]; then RUN_CMD="python3 manage.py runserver"; DEFAULT_URL="http://localhost:8000"
    else
      for f in main.py app.py server.py src/main.py app/main.py; do
        [ -f "$f" ] || continue
        mod="$(printf '%s' "${f%.py}" | tr / .)"
        if grep -q 'FastAPI' "$f"; then RUN_CMD="python3 -m uvicorn $mod:app --port 8000"; DEFAULT_URL="http://localhost:8000"; break
        elif grep -q 'Flask' "$f"; then RUN_CMD="python3 -m flask --app $mod run --port 5000"; DEFAULT_URL="http://localhost:5000"; break; fi
      done
    fi
  fi
fi

# ---- mode 1: command that must exit 0 --------------------------------------
if [ -n "$CHECK_CMD" ]; then
  bash -c "$CHECK_CMD" >"$LOG" 2>&1 &
  PID=$!
  while kill -0 "$PID" 2>/dev/null && [ "$SECONDS" -lt "$TIMEOUT" ]; do sleep 0.2; done
  if kill -0 "$PID" 2>/dev/null; then
    kill_tree
    write_result false "" "timeout" "$CHECK_CMD" "command did not exit within ${TIMEOUT}s"
    echo "smoke: FAIL (timeout) $CHECK_CMD"; exit 1
  fi
  wait "$PID" 2>/dev/null; RC=$?; PID=""
  if [ "$RC" -eq 0 ]; then
    write_result true "" "exit 0" "$CHECK_CMD" ""
    echo "smoke: OK ($CHECK_CMD exited 0)"; exit 0
  fi
  write_result false "" "exit $RC" "$CHECK_CMD" "$( (echo "exit code $RC"; tail -5 "$LOG") )"
  echo "smoke: FAIL ($CHECK_CMD exited $RC)"; exit 1
fi

if [ -z "$RUN_CMD" ]; then
  write_result false "${URL:-$DEFAULT_URL}" "no-command" "" "no start command found: set MOGGER_RUN_CMD, .claude/mogger.json run, STACK.md run:, or MOGGER_SMOKE_CMD"
  echo "smoke: FAIL (no start command detected)"; exit 1
fi

# ---- mode 2: server --------------------------------------------------------
bash -c "$RUN_CMD" >"$LOG" 2>&1 &
PID=$!
STATUS="000"; OKURL=""; DIED=""
have_curl=1; command -v curl >/dev/null 2>&1 || have_curl=0
probe() { curl -s -o /dev/null -w '%{http_code}' --max-time 2 "$1" 2>/dev/null; }
while [ "$SECONDS" -lt "$TIMEOUT" ]; do
  if ! kill -0 "$PID" 2>/dev/null; then DIED=1; break; fi
  if [ "$have_curl" -eq 0 ]; then break; fi
  if [ -n "$URL" ]; then CANDS="$URL"; else
    LOGURL=$(grep -Eo 'https?://(localhost|127\.0\.0\.1|0\.0\.0\.0|\[::1?\]):[0-9]+' "$LOG" 2>/dev/null | head -1 | sed -e 's#//0\.0\.0\.0#//localhost#' -e 's#//\[::1\{0,1\}\]#//localhost#')
    CANDS="$LOGURL $DEFAULT_URL"
  fi
  for u in $CANDS; do
    c=$(probe "$u"); STATUS="${c:-000}"
    case "$STATUS" in 2??|3??) OKURL="$u"; break ;; esac
  done
  [ -n "$OKURL" ] && break
  sleep 0.5
done
FINAL_URL="${OKURL:-${URL:-$DEFAULT_URL}}"

if [ "$have_curl" -eq 0 ]; then
  kill_tree
  write_result false "$FINAL_URL" "no-curl" "$RUN_CMD" "curl not available; cannot poll URL"
  echo "smoke: FAIL (curl missing)"; exit 1
fi

# give late output a moment, then scan
[ -n "$OKURL" ] && sleep 0.3
ERRS="$(scan_errors)"
RC_NOTE=""
if [ -n "$DIED" ]; then
  wait "$PID" 2>/dev/null; RC=$?; PID=""
  RC_NOTE="process exited early with code $RC"
fi

# optional browser pass (only if we have a live URL)
if [ -n "$OKURL" ] && [ "${MOGGER_SMOKE_SCREENSHOT:-off}" = "on" ]; then
  if command -v node >/dev/null 2>&1 && [ -f "$HERE/smoke-browser.mjs" ] && { [ -n "${PLAYWRIGHT_BROWSERS_PATH:-}" ] || command -v npx >/dev/null 2>&1; }; then
    BOUT="$(node "$HERE/smoke-browser.mjs" "$OKURL" "$STATE/smoke.png" 2>/dev/null)"; BRC=$?
    if [ "$BRC" -eq 3 ]; then NOTES="browser check skipped: playwright not installed"
    elif [ "$BRC" -ne 0 ]; then NOTES="browser check failed to run (exit $BRC)"
    else BROWSER_ERRS="$(printf '%s\n' "$BOUT" | grep -v '^SHOT ' | head -10)"; NOTES="screenshot: $STATE/smoke.png"; fi
  else
    NOTES="browser check skipped: node/playwright unavailable"
  fi
fi

kill_tree

if [ -n "$OKURL" ] && [ -z "$ERRS" ]; then
  write_result true "$OKURL" "$STATUS" "$RUN_CMD" ""
  echo "smoke: OK $OKURL -> $STATUS in ${SECONDS}s"; exit 0
fi
ALL="$ERRS"
[ -n "$RC_NOTE" ] && ALL="$RC_NOTE
$ALL"
[ -z "$OKURL" ] && [ -z "$DIED" ] && ALL="no 2xx/3xx from $FINAL_URL within ${TIMEOUT}s (last status $STATUS)
$ALL"
[ -z "$(printf '%s' "$ALL" | tr -d '[:space:]')" ] && ALL="failed without a recognizable error line; see $LOG"
write_result false "$FINAL_URL" "$STATUS" "$RUN_CMD" "$ALL"
echo "smoke: FAIL $FINAL_URL status=$STATUS"; printf '%s\n' "$ALL" | head -5
exit 1
