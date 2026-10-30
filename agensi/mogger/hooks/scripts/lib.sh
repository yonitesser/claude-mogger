#!/usr/bin/env bash
# Sourced by every hook. Provides json_get so hooks work with jq OR python3.
# Usage: VALUE=$(json_get "$INPUT" '.tool_input.file_path')

# json_fields <input> <jq-path>... -> fills the array JF with one value per path ("" when
# missing). One jq call for all of them instead of one per field. Falls back to json_get.
json_fields() {
  local input="$1" filt="" p i=0 out; shift
  JF=()
  if command -v jq >/dev/null 2>&1; then
    for p in "$@"; do filt="$filt${filt:+,}(($p) // \"\" | tostring)"; done
    out=$(printf '%s' "$input" | jq -j "[$filt] | join(\"\\u001f\") + \"\\u001f\"" 2>/dev/null)
    IFS=$'\x1f' read -r -d '' -a JF <<<"$out" || true
    [ "${#JF[@]}" -ge "$#" ] && return 0
    JF=()
  fi
  for p in "$@"; do JF[i]=$(json_get "$input" "$p"); i=$((i + 1)); done
}

# mogger_re <string> <ERE> -> success when the string matches (no fork; honours nocasematch).
# \s is not POSIX: macOS bash (regcomp without REG_ENHANCED) takes it as a plain "s", so spell it out.
mogger_re() { local p=${2//\\s/[[:space:]]}; [[ $1 =~ $p ]]; }

# mogger_rel_path <path> -> the path as seen from the project root, with a leading
# slash, so `*/build/*` style tests judge folders INSIDE the project and not the
# folders the project itself happens to live in (/work/payments-app/...).
mogger_rel_path() {
  local p="$1" root="${CLAUDE_PROJECT_DIR:-$PWD}"
  case "$p" in "$root"/*) p="${p#"$root"}" ;; esac
  case "$p" in /*) printf '%s' "$p" ;; *) printf '/%s' "$p" ;; esac
}

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


# Print the test command for this project, nothing if none is clearly set up.
mogger_test_cmd() {
  if [ -f package.json ]; then
    local t; t=$(json_get "$(cat package.json)" '.scripts.test')
    case "$t" in ''|*"no test specified"*) ;; *) echo "npm test --silent"; return ;; esac
  fi
  if [ -f pytest.ini ] || [ -f tox.ini ] || { [ -f pyproject.toml ] && grep -q 'pytest' pyproject.toml; }; then
    python3 -c 'import pytest' 2>/dev/null && { echo "python3 -m pytest -x -q"; return; }
  fi
  [ -f go.mod ] && { echo "go test ./..."; return; }
  [ -f Cargo.toml ] && { echo "cargo test -q"; return; }
}

# Toggles from .claude/mogger.json: {"danger-guard": "off", "push-guard": "ask", ...}.
# Names, the MOGGER_* variable each one maps to and the states it allows
# (on, ask, off) are in hooks/guards.tsv. A variable that is already set wins
# over the file. A missing, bad, unreadable or not-allowed value changes nothing,
# so the guard keeps its default. Runs when a hook sources this file.
# A safety guard set to "off" in a file that git tracks is ignored: a cloned repo
# must not be able to switch your guards off. Use an env var or an untracked file.
_mogger_load_config() {
  local f="${CLAUDE_PROJECT_DIR:-.}/.claude/mogger.json" cat pairs name val n e kind onv dflt on_t off_t states rest tracked="" rows
  cat="${BASH_SOURCE[0]%/*}/../guards.tsv"
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
  rows=$(grep -v '^#' "$cat")   # read the catalog once, not once per key
  while IFS=$'\t' read -r name val; do
    [ -n "$name" ] || continue
    while IFS=$'\t' read -r n e kind onv dflt on_t off_t states rest; do
      [ "$n" = "$name" ] || continue
      [ -z "${!e+x}" ] || continue
      case ",${states:-on,off}," in *",$val,"*) ;; *) continue ;; esac
      if [ "$val" = off ] && [ "$kind" = safety ]; then
        [ -n "$tracked" ] || tracked=$(git -C "${f%/*}" ls-files --error-unmatch mogger.json >/dev/null 2>&1 && echo yes || echo no)
        [ "$tracked" = yes ] && continue
      fi
      case "$val" in
        off) export "$e=off" ;;
        ask) export "$e=ask" ;;
        on) export "$e=$onv" ;;
      esac
    done <<<"$rows"
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

# mogger_text_maybe <text> <word>... -> 0 when the text contains any word (case-insensitive, globs ok).
# A cheap pre-filter: a hook that scans for a few risky words can stop before it forks grep/awk.
mogger_text_maybe() {
  local t="$1" g r=1 had=0; shift
  shopt -q nocasematch && had=1
  shopt -s nocasematch
  for g in "$@"; do [[ $t == *$g* ]] && { r=0; break; }; done
  [ "$had" = 1 ] || shopt -u nocasematch
  return $r
}

# mogger_prose_free <command> -> REPLY = the command with text that is only DATA taken out, so a
# commit message or echo that merely MENTIONS "git reset --hard" is not read as that command.
# Removed: heredoc bodies fed to `$(cat <<EOF` or `-F -`, and quoted spans that contain whitespace.
# Kept as is (REPLY = the original, status 1) when anything could run quoted text as code:
# sh/bash/eval/ssh/python/node/..., `-c`/`-e`, `$(`, backticks. Pure bash, no forks.
MOGGER_HEREDOC_RE='(\$\([[:space:]]*cat|(-F|--file|--body-file)[[:space:]]+-)[[:space:]]*<<-?[[:space:]]*["'\'']?([A-Za-z_][A-Za-z0-9_]*)["'\'']?'
MOGGER_WRAP_RE='\$\(|`|<\(|(^|[[:space:];&|(/])(sh|bash|zsh|dash|ksh|fish|eval|source|xargs|ssh|exec|su|watch|python[0-9.]*|node|nodejs|deno|bun|ruby|perl|php|osascript|pwsh|powershell|docker|podman|kubectl|nsenter|chroot|script)([[:space:]]|$)|[[:space:]]-(c|e|exec|command|eval)([[:space:]]|$)'
MOGGER_SPAN_RE='^([^"'\'']*)("[^"]*"|'\''[^'\'']*'\'')(.*)$'
mogger_prose_free() {
  local c="$1" m delim before after rest out="" span
  REPLY="$1"
  [[ $c == *'"'* || $c == *"'"* || $c == *'<<'* ]] || return 1
  while [[ $c =~ $MOGGER_HEREDOC_RE ]]; do
    m="${BASH_REMATCH[0]}"; delim="${BASH_REMATCH[3]}"
    before="${c%%"$m"*}"; after="${c#*"$m"}"
    m="${m/\$(/(}"; m="${m/<</< <}"   # neutralised, so the loop moves on and `$(` is not seen below
    case "$after" in
      *$'\n'*) rest=$'\n'"${after#*$'\n'}"; after="${after%%$'\n'*}"
               case "$rest" in *$'\n'"$delim"*) rest="${rest#*$'\n'"$delim"}" ;; *) rest="" ;; esac ;;
      *) rest="" ;;
    esac
    c="$before$m$after"$'\n'"$rest"
  done
  [[ $c =~ $MOGGER_WRAP_RE ]] && return 1
  while [[ $c =~ $MOGGER_SPAN_RE ]]; do
    span="${BASH_REMATCH[2]}"; out+="${BASH_REMATCH[1]}"; c="${BASH_REMATCH[3]}"
    case "$span" in *[[:space:]]*) out+="_" ;; *) out+="$span" ;; esac
  done
  REPLY="$out$c"
}
