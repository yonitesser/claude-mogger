#!/usr/bin/env bash
# PostToolUse AND PostToolUseFailure — matcher: Bash
# Writes the test evidence the reviewer gate trusts: .claude/state/test-evidence.json.
# THIS HOOK writes it, from the real result of a test command that ran in Bash.
# The tester agent's own marker (last_test_result.json) is only a claim; the gate
# (require-tests-pass.sh) also needs this file to say "pass". Edit/Write to the
# evidence file is blocked by protect-pipeline-files.sh. This is tamper-resistant,
# not tamper-proof: a shell command can still write the file.
#
# Payload shapes are the same as fix-loop-guard.sh (non-zero exit => PostToolUseFailure
# with "Exit code N" in .error; exit 0 => PostToolUse, no exit code, so a strong
# failure signature in piped output still counts as a fail).
# Only commands that look like TEST runs are recorded (lint/build alone are not).
# MOGGER_TEST_CMD_REGEX adds a project pattern. MOGGER_EVIDENCE=off disables.
# Always exits 0.
source "${0%/*}/lib.sh"
[ "${MOGGER_EVIDENCE:-on}" = "off" ] && exit 0
INPUT=$(cat); [ -n "$INPUT" ] || exit 0
CMD=$(json_get "$INPUT" '.tool_input.command'); [ -n "$CMD" ] || exit 0
case "$CMD" in
  echo\ *|printf\ *|cat\ *|grep\ *|rg\ *|ls\ *|git\ *|man\ *|which\ *|type\ *|sed\ *|head\ *|tail\ *) exit 0 ;;
esac
fl_recognised "$CMD" || exit 0
# test run, not just lint/build/typecheck
tre='(^|[^[:alnum:]_])(test|tests|pytest|py[.]test|jest|vitest|mocha|ava|tap|rspec|phpunit|tox|nox|unittest|playwright|cypress)([^[:alnum:]_]|$)'
if ! [[ "$CMD" =~ $tre ]]; then
  [ -n "${MOGGER_TEST_CMD_REGEX:-}" ] && [[ "$CMD" =~ ${MOGGER_TEST_CMD_REGEX} ]] || exit 0
fi

NL='
'
EVENT=$(json_get "$INPUT" '.hook_event_name'); ERRTXT=$(json_get "$INPUT" '.error')
STATUS=""; CODE=0
if [ "$EVENT" = "PostToolUseFailure" ] || [ -n "$ERRTXT" ]; then
  [ "$(json_get "$INPUT" '.is_interrupt')" = "true" ] && exit 0
  first="${ERRTXT%%"$NL"*}"
  case "$first" in
    "Exit code "*)
      CODE="${first#Exit code }"; CODE="${CODE%%[!0-9]*}"
      case "$CODE" in ''|*[!0-9]*) exit 0 ;; 0|126|127|130|137|143) exit 0 ;; esac
      STATUS=fail ;;
    *"timed out"*) STATUS=fail; CODE=timeout ;;
    *) exit 0 ;;
  esac
else
  [ "$(json_get "$INPUT" '.tool_response.interrupted')" = "true" ] && exit 0
  OUT=$(json_get "$INPUT" '.tool_response.stdout')
  ERRO=$(json_get "$INPUT" '.tool_response.stderr')
  [ -n "$ERRO" ] && OUT="${OUT}${NL}${ERRO}"
  CODE=$(json_get "$INPUT" '.tool_response.exit_code')
  [ -z "$CODE" ] && CODE=$(json_get "$INPUT" '.tool_response.exitCode')
  case "$CODE" in ''|0) CODE=0 ;; *[!0-9]*) exit 0 ;; 126|127|130|137|143) exit 0 ;; *) STATUS=fail ;; esac
  if [ "$CODE" = "0" ]; then
    sig_re='(^|[^0-9])[1-9][0-9]* (failed|failing)|--- FAIL|test result: FAILED|error TS[0-9]|^not ok |Traceback [(]most recent'
    if printf '%s\n' "$OUT" | head -c 200000 | grep -E -q -e "$sig_re"; then STATUS=fail; CODE=piped; else STATUS=pass; fi
  fi
fi
[ -n "$STATUS" ] || exit 0

DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/state"
mkdir -p "$DIR" 2>/dev/null || exit 0
CMDJ=$(printf '%s' "$CMD" | tr '\n\t\r' '   ' | cut -c1-200 | sed 's/\\/\\\\/g; s/"/\\"/g')
printf '{"status":"%s","exit_code":"%s","command":"%s","timestamp":"%s","recorded_by":"record-test-run.sh"}\n' \
  "$STATUS" "$CODE" "$CMDJ" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$DIR/test-evidence.json.$$" 2>/dev/null \
  && mv "$DIR/test-evidence.json.$$" "$DIR/test-evidence.json" 2>/dev/null
[ "$STATUS" = pass ] && mogger_event ok "tests passed"   # the status bar mod's "pass" moment
exit 0
