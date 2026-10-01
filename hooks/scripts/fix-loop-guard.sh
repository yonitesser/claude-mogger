#!/usr/bin/env bash
# PostToolUse AND PostToolUseFailure — matcher: Bash
# Breaks "fix loops": the AI is asked to fix a failing test, edits, re-runs, the
# SAME failure comes back, and it edits again - forever (or worse, each "fix"
# breaks two other things). This hook watches test/build/lint commands
# (npm/pnpm/yarn/bun test|lint|build, vitest, jest, mocha, pytest, go test,
# cargo test, make test, tsc, eslint, ruff, mypy, dotnet/mvn/gradle test ...).
#
# Payload shape (verified against https://code.claude.com/docs/en/hooks):
#   - a Bash command that exits NON-ZERO fires PostToolUseFailure with
#     {"hook_event_name":"PostToolUseFailure","tool_input":{"command":..},
#      "error":"Exit code 1\n<output>","is_interrupt":false}
#   - a Bash command that exits 0 fires PostToolUse with
#     {"tool_input":{"command":..},"tool_response":{"stdout":..,"stderr":..,"interrupted":..}}
#     (no exit code is provided there; exit_code/exitCode are honoured if a
#     future version adds them).
# So register this script under BOTH events. Pass/fail is decided from the exit
# code when present; for exit-0 runs (e.g. "npm test | tail") only a strong
# failure signature in the output counts as a failure ("2 failed", "--- FAIL",
# "test result: FAILED", "error TS1234"). Undeterminable => do nothing.
#
# State: .claude/state/fixloop.json {signature,count,first_ts,last_ts,...}.
# signature = command + first failing line normalised (digits, paths, hashes,
# ANSI removed). Same signature MOGGER_MAX_FIX_ATTEMPTS (default 3) times in a
# row => exit 2 with a "stop and rethink" message. A pass of the same command,
# or a different signature, resets the count. Failing-test count rising versus
# the previous run of the same command => one-time whack-a-mole WARN
# (stderr + additionalContext, exit 0).
# Escape hatches: MOGGER_FIX_LOOP_GUARD=off, MOGGER_MAX_FIX_ATTEMPTS=N,
# MOGGER_FIXLOOP_TTL=seconds (default 7200; older state is ignored).
# Fails OPEN on missing jq/python3, garbage input, unwritable state.
source "$(dirname "$0")/lib.sh"

[ "${MOGGER_FIX_LOOP_GUARD:-on}" = "off" ] && exit 0

INPUT=$(cat)
[ -n "$INPUT" ] || exit 0

CMD=$(json_get "$INPUT" '.tool_input.command')
[ -n "$CMD" ] || exit 0

# ---- is this a test/build/lint command? (cheap, before any other work)
fl_recognised() {
  local c="$1" re
  re='(^|[[:space:];&|(/])(npm|pnpm|yarn|bun)([[:space:]]+run)?[[:space:]]+(test|t|lint|build|typecheck|type-check|check|ci)([[:space:]]|$)'
  [[ "$c" =~ $re ]] && return 0
  re='(^|[[:space:];&|(/])(vitest|jest|mocha|ava|tap|playwright[[:space:]]+test|cypress[[:space:]]+run|tsc|eslint|biome|ruff|mypy|pyright|flake8|pylint|pytest|py[.]test|tox|nox|rspec|phpunit|golangci-lint|clippy)([[:space:]]|$)'
  [[ "$c" =~ $re ]] && return 0
  re='(^|[[:space:];&|(/])(go[[:space:]]+(test|build|vet)|cargo[[:space:]]+(test|build|check|clippy)|make[[:space:]]+(test|tests|check|lint|build)|dotnet[[:space:]]+(test|build)|mvn[[:space:]]+(test|verify|package)|gradle[[:space:]]+(test|build|check)|[.]/gradlew[[:space:]]+(test|build|check)|deno[[:space:]]+(test|lint|check)|bundle[[:space:]]+exec[[:space:]]+rspec)([[:space:]]|$)'
  [[ "$c" =~ $re ]] && return 0
  re='python[0-9.]*[[:space:]]+-m[[:space:]]+(pytest|unittest|mypy|ruff|tox)([[:space:]]|$)'
  [[ "$c" =~ $re ]] && return 0
  re='(^|[[:space:];&|(])(bash|sh)[[:space:]]+[^;&|]*test[^;&|]*[.]sh([[:space:]]|$)'
  [[ "$c" =~ $re ]] && return 0
  return 1
}
# not a run: echo/cat/grep/git/... merely MENTIONING a test command
case "$CMD" in
  echo\ *|printf\ *|cat\ *|grep\ *|rg\ *|ls\ *|git\ *|man\ *|which\ *|type\ *|sed\ *|head\ *|tail\ *) exit 0 ;;
esac
fl_recognised "$CMD" || exit 0

EVENT=$(json_get "$INPUT" '.hook_event_name')
ERRTXT=$(json_get "$INPUT" '.error')
NL='
'
STATE=".claude/state/fixloop.json"
STATUS=""; OUT=""

if [ "$EVENT" = "PostToolUseFailure" ] || [ -n "$ERRTXT" ]; then
  [ "$(json_get "$INPUT" '.is_interrupt')" = "true" ] && exit 0
  first="${ERRTXT%%"$NL"*}"
  case "$first" in
    "Exit code "*)
      CODE="${first#Exit code }"; CODE="${CODE%%[!0-9]*}"
      case "$CODE" in ''|*[!0-9]*) exit 0 ;; esac
      # 126/127 = cannot execute / not found, 130 = ctrl-c: not a test failure
      case "$CODE" in 0|126|127|130|137|143) exit 0 ;; esac
      STATUS=fail
      case "$ERRTXT" in *"$NL"*) OUT="${ERRTXT#*"$NL"}" ;; esac
      ;;
    *"timed out"*) STATUS=fail; CODE=timeout; OUT="$ERRTXT" ;;
    *) exit 0 ;;   # bare failure message (shell could not start etc.)
  esac
else
  OUT=$(json_get "$INPUT" '.tool_response.stdout')
  ERRO=$(json_get "$INPUT" '.tool_response.stderr')
  [ -n "$ERRO" ] && OUT="${OUT}${NL}${ERRO}"
  if [ -z "$OUT" ]; then OUT=$(json_get "$INPUT" '.tool_response'); fi
  [ "$(json_get "$INPUT" '.tool_response.interrupted')" = "true" ] && exit 0
  CODE=$(json_get "$INPUT" '.tool_response.exit_code')
  [ -z "$CODE" ] && CODE=$(json_get "$INPUT" '.tool_response.exitCode')
  case "$CODE" in
    ''|0) CODE=0 ;;
    *[!0-9]*) exit 0 ;;
    126|127|130|137|143) exit 0 ;;
    *) STATUS=fail ;;
  esac
  if [ "$CODE" = "0" ]; then
    # exit 0 (or unknown): only a strong failure signature (piped runs) counts
    sig_re='(^|[^0-9])[1-9][0-9]* (failed|failing)|--- FAIL|test result: FAILED|error TS[0-9]|^not ok |Traceback [(]most recent'
    if printf '%s\n' "$OUT" | head -c 200000 | grep -E -q -e "$sig_re"; then
      STATUS=fail; CODE=piped
    else
      STATUS=pass
    fi
  fi
fi
[ -n "$STATUS" ] || exit 0

NOW=$(date +%s 2>/dev/null); case "$NOW" in ''|*[!0-9]*) exit 0 ;; esac

# ---- normalise the command
NCMD=$(printf '%s' "$CMD" | tr -d '"\\' | tr '\n\t' '  ' | sed -e 's/[[:space:]][[:space:]]*/ /g' -e 's/^ //' -e 's/ $//' | cut -c1-160)

if [ "$STATUS" = "pass" ]; then
  if [ -f "$STATE" ]; then
    PC=$(json_get "$(cat "$STATE" 2>/dev/null)" '.cmd')
    [ "$PC" = "$NCMD" ] && rm -f "$STATE" 2>/dev/null
  fi
  exit 0
fi

# ---- failure: first failing line, normalised
ESC=$(printf '\033')
OUT=$(printf '%s\n' "$OUT" | head -c 200000 | sed "s/${ESC}\[[0-9;]*[A-Za-z]//g")
FAILLINE=$(printf '%s\n' "$OUT" | grep -E -m1 -e '(^|[[:space:]])(FAIL|FAILED|not ok|--- FAIL)([[:space:]]|:|$)|✕|✗|×|●' )
[ -z "$FAILLINE" ] && FAILLINE=$(printf '%s\n' "$OUT" | grep -E -m1 -e 'AssertionError|TypeError|ReferenceError|SyntaxError|Traceback|panicked|error TS|Error|error|assert|Expected|expected')
[ -z "$FAILLINE" ] && FAILLINE=$(printf '%s\n' "$OUT" | grep -v -E '^[[:space:]]*$' | tail -n 1)
[ -z "$FAILLINE" ] && FAILLINE="exit $CODE"
NLINE=$(printf '%s' "$FAILLINE" | tr -d '"\\' | tr -d '[:cntrl:]' \
  | sed -E -e 's/[0-9a-fA-F]{8,}//g' -e 's#[^[:space:]]*/##g' -e 's/[0-9]+//g' -e 's/[[:space:]]+/ /g' -e 's/^ //' -e 's/ $//' | cut -c1-160)
[ -z "$NLINE" ] && NLINE="exit $CODE"
SIG="${NCMD} :: ${NLINE}"

# ---- failing-test count (for whack-a-mole)
FAILED=$(printf '%s\n' "$OUT" | sed -n -E 's/^Tests:.*[^0-9]([0-9]+) failed.*/\1/p' | head -n 1)
[ -z "$FAILED" ] && FAILED=$(printf '%s\n' "$OUT" | sed -n -E 's/(^|.*[^0-9])([0-9]+) (failed|failing).*/\2/p' | head -n 1)
if [ -z "$FAILED" ]; then
  FAILED=$(printf '%s\n' "$OUT" | grep -c -E -e '^[[:space:]]*(--- FAIL|not ok)|✕|✗')
  case "$FAILED" in ''|*[!0-9]*|0) FAILED=-1 ;; esac
fi

MAX="${MOGGER_MAX_FIX_ATTEMPTS:-3}"; case "$MAX" in ''|*[!0-9]*|0) MAX=3 ;; esac
TTL="${MOGGER_FIXLOOP_TTL:-7200}"; case "$TTL" in ''|*[!0-9]*) TTL=7200 ;; esac

P_SIG=""; P_COUNT=0; P_FIRST=$NOW; P_LAST=0; P_FAILED=-1; P_CMD=""; P_WARNED=0
if [ -f "$STATE" ]; then
  ST=$(cat "$STATE" 2>/dev/null)
  P_SIG=$(json_get "$ST" '.signature'); P_COUNT=$(json_get "$ST" '.count')
  P_FIRST=$(json_get "$ST" '.first_ts'); P_LAST=$(json_get "$ST" '.last_ts')
  P_FAILED=$(json_get "$ST" '.failed'); P_CMD=$(json_get "$ST" '.cmd'); P_WARNED=$(json_get "$ST" '.warned')
  for v in P_COUNT P_FIRST P_LAST P_WARNED; do
    eval "case \"\$$v\" in ''|*[!0-9]*) $v=0 ;; esac"
  done
  case "$P_FAILED" in ''|-1|*[!0-9]*) P_FAILED=-1 ;; esac
  [ "$P_FIRST" -gt 0 ] || P_FIRST=$NOW
  # stale state (older than TTL) is ignored
  if [ "$P_LAST" -gt 0 ] && [ $((NOW - P_LAST)) -gt "$TTL" ]; then P_SIG=""; P_COUNT=0; P_FIRST=$NOW; P_CMD=""; P_FAILED=-1; P_WARNED=0; fi
fi

if [ "$P_SIG" = "$SIG" ]; then COUNT=$((P_COUNT + 1)); FIRST=$P_FIRST; else COUNT=1; FIRST=$NOW; fi

WARNED=0; WOULD_WARN=0
if [ "$P_CMD" = "$NCMD" ]; then
  WARNED=$P_WARNED
  if [ "$FAILED" -ge 0 ] && [ "$P_FAILED" -ge 0 ] && [ "$FAILED" -gt "$P_FAILED" ] && [ "$WARNED" -eq 0 ]; then
    WOULD_WARN=1; WARNED=1
  fi
fi

if mkdir -p .claude/state 2>/dev/null; then
  TMP="${STATE}.$$"
  printf '{"signature":"%s","count":%s,"first_ts":%s,"last_ts":%s,"failed":%s,"cmd":"%s","warned":%s}\n' \
    "$SIG" "$COUNT" "$FIRST" "$NOW" "$FAILED" "$NCMD" "$WARNED" > "$TMP" 2>/dev/null && mv "$TMP" "$STATE" 2>/dev/null
  rm -f "$TMP" 2>/dev/null
fi

fl_json_escape() {
  printf '%s' "$1" | tr '\t' ' ' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | awk 'BEGIN{ORS="\\n"}{print}'
}

WARNMSG=""
if [ "$WOULD_WARN" -eq 1 ]; then
  WARNMSG="WARN (whack-a-mole): failing tests went from ${P_FAILED} to ${FAILED} since the previous run of '${NCMD}'. The last edit probably broke something new. Look at what changed (git diff), and revert that edit before adding another fix on top."
fi

if [ "$COUNT" -ge "$MAX" ]; then
  {
    echo "STOP the fix loop. '${NCMD}' has now failed ${COUNT} times in a row with the same error (${NLINE})."
    echo "Do not make another edit for this failure yet. Instead:"
    echo "  1. State the hypothesis you have NOT yet verified (what you believe the cause is, and what you have not actually checked)."
    echo "  2. Run: bash scripts/mogger-rewind.sh list   and consider restoring the last good checkpoint."
    echo "  3. Re-read the failing test itself - is it testing what you think it is?"
    echo "  4. If new failures appeared after your last edit, say so and revert that edit."
    echo "  5. If the advisor tool is on (/advisor), ask it for a second opinion now."
    echo "  6. Then ask the user before trying again."
    [ -n "$WARNMSG" ] && echo "$WARNMSG"
    echo "(Set MOGGER_MAX_FIX_ATTEMPTS to change the threshold; MOGGER_FIX_LOOP_GUARD=off disables this guard.)"
  } >&2
  exit 2
fi

if [ -n "$WARNMSG" ]; then
  echo "$WARNMSG" >&2
  HE="${EVENT:-PostToolUse}"
  case "$HE" in PostToolUse|PostToolUseFailure) ;; *) HE=PostToolUse ;; esac
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$HE" "$(fl_json_escape "$WARNMSG")"
fi
exit 0
