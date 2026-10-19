#!/usr/bin/env bash
# Not a hook. Called by the tester agent and the Lead while work is in progress.
# Prints which tests to run for the files that changed, so a small edit does not
# pay for the whole suite. Two lines on stdout:
#   scope: affected | full
#   command: <what to run>
# The full suite still runs once before "done" (stop-tests-added.sh, and the
# tester's final pass). This only picks the in-between runs.
# "affected" is printed only when every changed file maps to a test. Anything
# else (config, lockfile, docs, a source file with no test, no known runner)
# gives "full". No dependencies: the project's own related-tests tool when it
# has one (jest --findRelatedTests, vitest related), else a name and import match.
# Usage: related-tests.sh [file ...]   (no files: git changes, else .claude/state/edits.log)
# Exit 1 and no output when the project has no test command at all.
# Toggle: related-tests / MOGGER_RELATED_TESTS=off always prints "full".
source "${0%/*}/lib.sh"
MOGGER_TQ_SOURCE_ONLY=1 source "${0%/*}/check-test-quality.sh" 2>/dev/null

FULL=$(mogger_test_cmd)
say() { printf 'scope: %s\ncommand: %s\n' "$1" "$2"; exit 0; }
full() { [ -n "$FULL" ] || exit 1; say full "$FULL"; }

[ "${MOGGER_RELATED_TESTS:-on}" = off ] && full

FILES=("$@")
if [ ${#FILES[@]} -eq 0 ]; then
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    while IFS= read -r l; do FILES+=("$l"); done < <(git status --porcelain --untracked-files=all 2>/dev/null | sed -e 's/^...//' -e 's/.* -> //' -e 's/^"//' -e 's/"$//')
  elif [ -f .claude/state/edits.log ]; then
    while IFS= read -r l; do FILES+=("$l"); done < <(cut -c3- .claude/state/edits.log | sort -u)
  fi
fi
[ ${#FILES[@]} -gt 0 ] || full

is_test() { tq_is_test_path "$1" || case "${1##*/}" in *.test.sh|test_*.sh|*_test.sh) return 0 ;; *) return 1 ;; esac; }
dep() { [ -f package.json ] && grep -q "\"$1\"" package.json; }

# one pass over the changed files: tests stay, code is kept as a source, the rest means "full"
SRC=(); TESTS=()
for f in "${FILES[@]}"; do
  [ -e "$f" ] || continue   # deleted file: nothing to run for it, the full run covers it
  if is_test "$f"; then TESTS+=("$f"); continue; fi
  case "${f##*.}" in
    py|js|jsx|ts|tsx|mjs|cjs|go|sh) SRC+=("$f") ;;
    *) full ;;
  esac
done
[ $((${#SRC[@]} + ${#TESTS[@]})) -gt 0 ] || full

# the project's own tool follows the real import graph; use it when there is one
if [ ${#SRC[@]} -gt 0 ] && [ ${#TESTS[@]} -eq 0 ]; then
  if dep vitest; then say affected "npx vitest related --run $(printf '%q ' "${SRC[@]}")"; fi
  if dep jest; then say affected "npx jest --findRelatedTests $(printf '%q ' "${SRC[@]}")--passWithNoTests"; fi
fi

# no tool: tests that sit next to the file by name, or mention its name as a word (an import)
if [ ${#SRC[@]} -gt 0 ]; then
  ALL=()
  while IFS= read -r t; do is_test "${t#./}" && ALL+=("${t#./}"); done < <(find . -type f \
    -not -path './.git/*' -not -path '*/node_modules/*' -not -path '*/.venv/*' -not -path '*/dist/*' -not -path '*/build/*' \
    -not -path './incoming/*' 2>/dev/null | head -5000)
  for s in "${SRC[@]}"; do
    stem="${s##*/}"; stem="${stem%.*}"; hit=0
    # an index/main file is imported by its folder name, not by "index"
    case "$stem" in index|main|mod|__init__) stem="${s%/*}"; stem="${stem##*/}" ;; esac
    [ -n "$stem" ] || full
    for t in "${ALL[@]}"; do
      [ "$t" = "$s" ] && continue
      # Go tests share the package, so they never name the file: a *_test.go in the same folder counts
      if { [ "${s##*.}" = go ] && [ "${t%/*}" = "${s%/*}" ] && [ "${t##*.}" = go ]; } || grep -qw -e "$stem" "$t" 2>/dev/null; then hit=1; TESTS+=("$t"); fi
    done
    [ "$hit" -eq 1 ] || full   # a changed file nobody tests: be safe, run everything
  done
fi

UNIQ=(); while IFS= read -r t; do [ -n "$t" ] && UNIQ+=("$t"); done < <(printf '%s\n' "${TESTS[@]}" | sort -u)
[ ${#UNIQ[@]} -gt 0 ] || full

# runner by file type; mixed types or an unknown runner means "full"
KIND=""
for t in "${UNIQ[@]}"; do
  case "${t##*.}" in py) k="py" ;; go) k="go" ;; sh) k="sh" ;; js|jsx|ts|tsx|mjs|cjs) k="js" ;; *) full ;; esac
  [ -z "$KIND" ] || [ "$KIND" = "$k" ] || full
  KIND=$k
done
case "$KIND" in
  py) python3 -c 'import pytest' 2>/dev/null || full
      say affected "python3 -m pytest -x -q $(printf '%q ' "${UNIQ[@]}")" ;;
  go) D=(); while IFS= read -r d; do D+=("./$d"); done < <(for t in "${UNIQ[@]}"; do d="${t%/*}"; [ "$d" = "$t" ] && d=.; echo "$d"; done | sort -u)
      say affected "go test $(printf '%q ' "${D[@]}")" ;;
  sh) c=""; for t in "${UNIQ[@]}"; do c="${c}${c:+ && }bash $(printf '%q' "$t")"; done
      say affected "$c" ;;
  js) dep vitest && say affected "npx vitest run $(printf '%q ' "${UNIQ[@]}")"
      dep jest && say affected "npx jest $(printf '%q ' "${UNIQ[@]}")"
      dep mocha && say affected "npx mocha $(printf '%q ' "${UNIQ[@]}")"
      full ;;
esac
full
