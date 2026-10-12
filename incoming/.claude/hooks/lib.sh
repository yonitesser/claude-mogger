#!/usr/bin/env bash
# Sourced by every hook. Provides json_get so hooks work with jq OR python3.
# Usage: VALUE=$(json_get "$INPUT" '.tool_input.file_path')

json_get() {
  local input="$1" path="$2"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -r "${path} // empty" 2>/dev/null
  elif command -v python3 >/dev/null 2>&1 && python3 -c '1' >/dev/null 2>&1; then
    # the python3 -c '1' probe rejects the Windows Store stub, which
    # exists on PATH but doesn't run anything — just prints an install nag
    printf '%s' "$input" | python3 -c '
import sys, json
path = sys.argv[1].lstrip(".").split(".")
try:
    obj = json.load(sys.stdin)
    for k in path:
        obj = obj[k]
    if obj is None: sys.exit(0)
    print(obj if not isinstance(obj, bool) else str(obj).lower())
except Exception:
    pass
' "$path"
  else
    # Neither tool available — fail open (return empty) rather than block
    # every tool call. session-start.sh warns the user about this.
    printf ''
  fi
}

# Current git branch, empty if not in a repo
git_branch() {
  git rev-parse --abbrev-ref HEAD 2>/dev/null || printf ''
}

# Is this branch one we treat as protected? Override with MOGGER_PROTECTED_BRANCHES="main|master|prod|release/.*"
is_protected_branch() {
  local b="$1" pat="${MOGGER_PROTECTED_BRANCHES:-main|master|prod|production|release/.*}"
  [[ "$b" =~ ^($pat)$ ]]
}

# mogger_event KIND "short message" — append one line (epoch<TAB>kind<TAB>message)
# to $CLAUDE_PROJECT_DIR/.claude/state/mogger-events.log so a Claude Code mod
# (mods/mogger-status) can show that mogger is working. KIND: block|warn|ok.
# Fail-open: prints nothing, always returns 0. Keep messages short, plain, no
# secrets, no command text: file basenames only. File is capped near 200 lines.
mogger_event() {
  (
    local dir f kind msg n
    dir="${CLAUDE_PROJECT_DIR:-.}/.claude/state"
    f="$dir/mogger-events.log"
    kind=$(printf '%s' "${1:-}" | tr -c 'a-z' '_' | cut -c1-12)
    msg=$(printf '%s' "${2:-}" | tr '\t\r\n' '   ' | tr -d '[:cntrl:]' | cut -c1-120)
    [ -n "$kind" ] && [ -n "$msg" ] || exit 0
    mkdir -p "$dir" || exit 0
    printf '%s\t%s\t%s\n' "$(date +%s)" "$kind" "$msg" >> "$f" || exit 0
    n=$(wc -l < "$f" | tr -d '[:space:]')
    case "$n" in ''|*[!0-9]*) exit 0 ;; esac
    if [ "$n" -gt 240 ]; then
      tail -n 200 "$f" > "$f.$$" && mv "$f.$$" "$f"
      rm -f "$f.$$"
    fi
  ) >/dev/null 2>&1
  return 0
}

# Is this Bash command a test/build/lint run? Shared by fix-loop-guard.sh and
# record-test-run.sh. MOGGER_TEST_CMD_REGEX adds a project-specific pattern.
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
  if [ -n "${MOGGER_TEST_CMD_REGEX:-}" ]; then
    [[ "$c" =~ ${MOGGER_TEST_CMD_REGEX} ]] && return 0
  fi
  return 1
}


# Toggles from .claude/mogger.json: {"danger-guard": "off", "push-guard": "ask", ...}.
# Names, the MOGGER_* variable each one maps to and the states it allows
# (on, ask, off) are in hooks/guards.tsv. A variable that is already set wins
# over the file. A missing, bad, unreadable or not-allowed value changes nothing,
# so the guard keeps its default. Runs when a hook sources this file.
_mogger_load_config() {
  local f="${CLAUDE_PROJECT_DIR:-.}/.claude/mogger.json" cat pairs name val n e kind onv dflt on_t off_t states rest
  cat="$(dirname "${BASH_SOURCE[0]}")/../guards.tsv"
  [ -f "$f" ] && [ -f "$cat" ] || return 0
  if command -v jq >/dev/null 2>&1; then
    pairs=$(jq -r 'to_entries[] | select(.value|type=="string") | "\(.key)\t\(.value)"' "$f" 2>/dev/null) || return 0
  elif command -v python3 >/dev/null 2>&1; then
    pairs=$(python3 -I -c 'import json,sys
for k,v in json.load(open(sys.argv[1])).items():
    if isinstance(v,str): print(k+"\t"+v)' "$f" 2>/dev/null) || return 0
  else
    return 0
  fi
  while IFS=$'\t' read -r name val; do
    [ -n "$name" ] || continue
    while IFS=$'\t' read -r n e kind onv dflt on_t off_t states rest; do
      [ "$n" = "$name" ] || continue
      [ -z "${!e+x}" ] || continue
      case ",${states:-on,off}," in *",$val,"*) ;; *) continue ;; esac
      case "$val" in
        off) export "$e=off" ;;
        ask) export "$e=ask" ;;
        on) export "$e=$onv" ;;
      esac
    done < <(grep -v '^#' "$cat")
  done <<<"$pairs"
  return 0
}
_mogger_load_config

# --- the third state: "ask" -------------------------------------------------
# A guard that can ask has three states: on (block), ask (the human gets a
# permission prompt and decides), off (allow). The agent cannot answer the
# prompt itself. Where no prompt can be shown, ask falls back to block.

# mogger_state <ENV_VAR> <default> -> prints on | ask | off.
# Anything else (a typo, "maybe") gives the default.
mogger_state() {
  case "${!1:-}" in
    off) echo off ;;
    ask) echo ask ;;
    on) echo on ;;
    *) echo "$2" ;;
  esac
}

# mogger_can_ask <hook input json>: can a human answer a prompt here?
# No when permission checks are off or automatic (bypassPermissions, dontAsk,
# auto), in headless/SDK runs, or when MOGGER_HEADLESS=on says so. A prompt
# the harness cannot show is auto-allowed or auto-denied; either way the human
# did not decide, so the hook blocks instead.
mogger_can_ask() {
  [ "${MOGGER_HEADLESS:-off}" = "on" ] && return 1
  case "${CLAUDE_CODE_ENTRYPOINT:-}" in sdk-*) return 1 ;; esac
  case "$(json_get "$1" '.permission_mode')" in bypassPermissions|dontAsk|auto) return 1 ;; esac
  return 0
}

# mogger_ask_json <reason>: the permission "ask" answer for a PreToolUse hook.
# Quotes, backslashes and control characters are dropped from the reason.
mogger_ask_json() {
  local r
  r=$(printf '%s' "$1" | tr -d '"\\' | tr '\n\t\r' '   ')
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s"}}\n' "$r"
}
