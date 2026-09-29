#!/usr/bin/env bash
# Project-wide, REPORT-ONLY test-quality check. Never modifies the project,
# always exits 0. Output: one line per finding  LEVEL|check-id|message
# (LEVEL = PASS WARN FAIL SKIP; messages carry file:line evidence).
#
# Reuses the scanner in hooks/scripts/check-test-quality.sh so the hook and this
# report can never disagree about what a "fake test" is.
#   FAIL  tests with no assertion / empty / tautologies / committed .only  (high confidence)
#   WARN  skipped tests, mock-only tests, unmatched source files,
#         no error/empty/invalid test names            (all HEURISTICS, labelled)
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="${1:-.}"
cd "$ROOT" 2>/dev/null || { echo "SKIP|tests-inventory|cannot enter $ROOT"; exit 0; }

LIB="$HERE/../../hooks/scripts/check-test-quality.sh"                # plugin layout
[ -f "$LIB" ] || LIB="$HERE/../.claude/hooks/check-test-quality.sh"  # manual-install layout
if [ ! -f "$LIB" ]; then
  echo "SKIP|tests-inventory|scanner missing ($LIB)"
  exit 0
fi
MOGGER_TQ_SOURCE_ONLY=1
export MOGGER_TQ_SOURCE_ONLY
# shellcheck disable=SC1090
. "$LIB" 2>/dev/null
unset MOGGER_TQ_SOURCE_ONLY

WORK=$(mktemp -d "${TMPDIR:-/tmp}/mogger-tqc.XXXXXX") || { echo "SKIP|tests-inventory|no temp dir"; exit 0; }
trap 'rm -rf "$WORK"; rm -f "${TQ_AWK:-}"' EXIT

find . \( -name node_modules -o -name .git -o -name dist -o -name build -o -name venv -o -name .venv -o -name env -o -name target -o -name vendor -o -name .next -o -name coverage -o -name __pycache__ -o -name .tox -o -name .claude -o -name out \) -prune -o -type f \
  \( -name '*.py' -o -name '*.js' -o -name '*.jsx' -o -name '*.ts' -o -name '*.tsx' -o -name '*.mjs' -o -name '*.cjs' -o -name '*.go' \) -print 2>/dev/null \
  | sed 's#^\./##' | sort | head -n 5000 > "$WORK/all.txt"

: > "$WORK/tests.txt"; : > "$WORK/src.txt"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if tq_is_test_path "$f"; then echo "$f" >> "$WORK/tests.txt"; else
    b="${f##*/}"
    case "$b" in
      *.d.ts|*.config.*|index.*|__init__.py|setup.py|conftest.py|main.go|*.min.js|.eslintrc*|types.ts|constants.*) ;;
      *) echo "$f" >> "$WORK/src.txt" ;;
    esac
  fi
done < "$WORK/all.txt"

NT=$(wc -l < "$WORK/tests.txt" | tr -d ' ')
NS=$(wc -l < "$WORK/src.txt" | tr -d ' ')

if [ "$NT" -eq 0 ] && [ "$NS" -eq 0 ]; then
  echo "SKIP|tests-inventory|no py/js/ts/go source or test files found"
  echo "SKIP|tests-no-assertions|no test files"
  echo "SKIP|tests-tautologies|no test files"
  echo "SKIP|tests-skipped|no test files"
  echo "SKIP|tests-unhappy-paths|no test files"
  exit 0
fi

if [ "$NT" -eq 0 ]; then
  echo "WARN|tests-inventory|0 test files vs $NS source files - nothing proves this code works"
  echo "SKIP|tests-no-assertions|no test files"
  echo "SKIP|tests-tautologies|no test files"
  echo "SKIP|tests-skipped|no test files"
  echo "SKIP|tests-unhappy-paths|no test files"
  exit 0
fi

# ---- scan every test file once
: > "$WORK/find.txt"
NTESTS=0
while IFS= read -r f; do
  tq_scan_file "$f" >> "$WORK/find.txt"
done < "$WORK/tests.txt"
while IFS='|' read -r kind file line msg; do
  [ "$kind" = "TESTS" ] && NTESTS=$((NTESTS + ${msg:-0}))
done < "$WORK/find.txt"

echo "PASS|tests-inventory|$NT test files, $NS source files, $NTESTS individual tests detected"

# report <check-id> <level> <ok-message> <kind...>
report() {
  local id="$1" level="$2" okmsg="$3" shown=0 total=0 kinds=" $4 $5 $6 " kind file line msg
  while IFS='|' read -r kind file line msg; do
    case "$kinds" in *" $kind "*) ;; *) continue ;; esac
    total=$((total + 1))
    if [ "$shown" -lt 15 ]; then
      echo "$level|$id|$file:$line $msg"
      shown=$((shown + 1))
    fi
  done < "$WORK/find.txt"
  if [ "$total" -eq 0 ]; then echo "PASS|$id|$okmsg"
  elif [ "$total" -gt "$shown" ]; then echo "$level|$id|... and $((total - shown)) more ($total total)"
  fi
}
report tests-no-assertions FAIL "no empty or assertion-less tests found in $NT files" EMPTY NOASSERT
report tests-tautologies FAIL "no tautological assertions found" TAUT
report tests-focused FAIL "no committed .only / fit / fdescribe" ONLY
report tests-skipped WARN "no skipped tests without a reason" SKIP
report tests-mock-only WARN "no mock-only tests detected (heuristic)" MOCK

# ---- source files with no matching test (HEURISTIC: name match only)
: > "$WORK/stems.txt"
while IFS= read -r f; do
  b="${f##*/}"; b="${b%.*}"
  b="${b%.test}"; b="${b%.spec}"; b="${b%_test}"
  case "$b" in test_*) b="${b#test_}" ;; esac
  echo "T|$b" >> "$WORK/stems.txt"
done < "$WORK/tests.txt"
while IFS= read -r f; do
  b="${f##*/}"; b="${b%.*}"
  echo "S|$f|$b" >> "$WORK/stems.txt"
done < "$WORK/src.txt"
awk -F'|' '$1=="T"{t[$2]=1} $1=="S"{ if(!($3 in t)) print $2 }' "$WORK/stems.txt" > "$WORK/untested.txt"
NU=$(wc -l < "$WORK/untested.txt" | tr -d ' ')
if [ "$NS" -eq 0 ]; then
  echo "SKIP|tests-untested-sources|no non-test source files to compare"
else
  PCT=$((NU * 100 / NS))
  EX=$(head -n 5 "$WORK/untested.txt" | tr '\n' ' ')
  if [ "$PCT" -gt 50 ]; then
    echo "WARN|tests-untested-sources|HEURISTIC: $NU of $NS source files ($PCT%) have no test file with a matching name, e.g. $EX"
  else
    echo "PASS|tests-untested-sources|HEURISTIC: $NU of $NS source files ($PCT%) have no test file with a matching name"
  fi
fi

# ---- does any test exercise an error / empty / invalid case? (HEURISTIC: names)
HITS=0; FIRSTHIT=""
UP_WORDS='empty|blank|null|undefined|invalid|malformed|raises|throws|throw|timeout|timed out|offline|error|fails|failure|missing|unauthori|forbidden|denied|reject|whitespace|duplicate|negative|wrong|bad_|bad |not found|500'
while IFS= read -r f; do
  H=$(awk -v W="$UP_WORDS" '
    { l = tolower($0) }
    (l ~ /(^|[^[:alnum:]_])(it|test|describe)[.a-z]*[[:space:]]*[(]/ || l ~ /def[[:space:]]+test/ || l ~ /func[[:space:]]+test/ || l ~ /toThrow|pytest[.]raises|assertRaises|[.]rejects/) && l ~ W { print FILENAME ":" NR; exit }
  ' "$f" 2>/dev/null)
  if [ -n "$H" ]; then
    HITS=$((HITS + 1))
    [ -z "$FIRSTHIT" ] && FIRSTHIT="$H"
  fi
done < "$WORK/tests.txt"
if [ "$HITS" -gt 0 ]; then
  echo "PASS|tests-unhappy-paths|$HITS of $NT test files mention an error/empty/invalid case, e.g. $FIRSTHIT (heuristic on test names)"
else
  echo "WARN|tests-unhappy-paths|HEURISTIC: no test name in $NT test files mentions empty/null/invalid/error/timeout/raises/throws - only the happy path may be tested"
fi
exit 0
