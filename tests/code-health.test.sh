#!/usr/bin/env bash
# Tests for the code-health layer. Run: bash tests/code-health.test.sh
#   hooks:  check-structure.sh, check-resilience.sh (exit 0 = allow, 2 = block)
#   checks: scripts/checks/{structure,resilience,database,cost-risk}.sh
#           (report-only: `LEVEL|check-id|message`, always exit 0)
# Self-contained temp sandbox, no network. Many cases are FALSE-POSITIVE guards.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
H="$ROOT/hooks/scripts"
C="$ROOT/scripts/checks"
PASS=0; FAIL=0

if ! command -v jq >/dev/null 2>&1 && { ! command -v python3 >/dev/null 2>&1 || ! python3 -c '1' >/dev/null 2>&1; }; then
  echo "neither jq nor python3 available: hooks fail open; nothing to test"; exit 0
fi

SANDBOX=$(mktemp -d 2>/dev/null || mktemp -d -t mogger-ch)
trap 'rm -rf "$SANDBOX"' EXIT
cd "$SANDBOX"

mkjson() {  # mkjson <tool> <abs file> [new_string] [old_string]
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg t "$1" --arg f "$2" --arg n "${3:-}" --arg o "${4:-}" \
      '{tool_name:$t,tool_input:({file_path:$f}+(if $n!="" then {new_string:$n} else {} end)+(if $o!="" then {old_string:$o} else {} end))}'
  else
    python3 -c 'import json,sys
t,f,n,o=sys.argv[1:5]
ti={"file_path":f}
if n: ti["new_string"]=n
if o: ti["old_string"]=o
print(json.dumps({"tool_name":t,"tool_input":ti}))' "$1" "$2" "${3:-}" "${4:-}"
  fi
}
w() {  # w <path> <content>   (relative to the current directory)
  mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" > "$1"
}
gen() {  # gen <path> <ndefs> <body-lines-per-def> py|js  : distinct, realistic-looking code
  mkdir -p "$(dirname "$1")"
  awk -v nd="$2" -v nb="$3" -v lang="$4" 'BEGIN {
    for (i=1;i<=nd;i++) {
      if (lang=="py") printf "def handler_%d(payload):\n", i; else printf "function handler_%d(payload) {\n", i
      for (j=1;j<=nb;j++) {
        if (lang=="py") printf "    value_%d_%d = payload.get(\"field_%d\", %d) + %d\n", i, j, j, i*7, j*3
        else printf "  const value_%d_%d = payload.field_%d + %d * %d;\n", i, j, j, i*7, j*3
      }
      if (lang=="py") printf "    return value_%d_1\n\n", i; else printf "  return value_%d_1;\n}\n\n", i
    } }' > "$1"
}
lines() { wc -l < "$SANDBOX/$1" | tr -d ' '; }

pass() { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

ERRF="$SANDBOX/.stderr"; RC=0
hook() {  # hook <script> <rel file> [VAR=val]   uses TOOL / NEW / OLD if set
  local script="$1" file="$2" envv="${3:-X=1}"
  mkjson "${TOOL:-Write}" "$SANDBOX/$file" "${NEW:-}" "${OLD:-}" | env "$envv" bash "$H/$script" >/dev/null 2>"$ERRF"; RC=$?
}
expect() {  # expect <script> <want exit> <rel file> <desc> [env assignment]
  hook "$1" "$3" "${5:-X=1}"
  if [ "$RC" -eq "$2" ]; then pass "$4"; else fail "$4 (want $2, got $RC)"; fi
}
errhas() {  # errhas <regex> <desc>   (against stderr of last hook call)
  if grep -q -E "$1" "$ERRF"; then pass "$2"; else fail "$2 (stderr: $(head -c 200 "$ERRF"))"; fi
}

OUT=""; ORC=0
run() {  # run <script> <dir>: capture stdout of a report-only check
  OUT=$(cd "$2" && bash "$C/$1" . 2>/dev/null); ORC=$?
}
has() {  # has <regex> <desc>
  if printf '%s\n' "$OUT" | grep -q -E "$1"; then pass "$2"; else fail "$2 (no match for: $1)"; fi
}
hasnt() {  # hasnt <regex> <desc>
  if printf '%s\n' "$OUT" | grep -q -E "$1"; then fail "$2 (unexpected match for: $1)"; else pass "$2"; fi
}
rcz() { if [ "$ORC" -eq 0 ]; then pass "$1"; else fail "$1 (exit $ORC)"; fi; }
contract() {  # every stdout line is LEVEL|id|message
  local bad
  bad=$(printf '%s\n' "$OUT" | grep -v -E '^(PASS|WARN|FAIL|SKIP)\|[a-z0-9-]+\|.+' | head -1)
  if [ -z "$bad" ]; then pass "$1: output contract (LEVEL|check-id|message)"; else fail "$1: bad line: $bad"; fi
}

# =====================================================================
echo "== hook: check-structure.sh (file size)"
w s/small.py 'def a():
    return 1'
expect check-structure.sh 0 s/small.py "small file allowed"

gen s/big.py 90 8 py     # 90 * 11 lines = ~990
expect check-structure.sh 2 s/big.py "file over 800 lines blocked"
errhas "$(lines s/big.py) lines" "message carries the exact line count"
errhas 'Suggested split' "message carries a split suggestion"
errhas 'handler_1' "suggestion names real top-level definitions"
errhas 's/big.py|big.py' "message names the file"
expect check-structure.sh 0 s/big.py "MOGGER_CHECK_STRUCTURE=off disables" MOGGER_CHECK_STRUCTURE=off
expect check-structure.sh 0 s/big.py "raising MOGGER_MAX_FILE_LINES allows" MOGGER_MAX_FILE_LINES=2000
expect check-structure.sh 2 s/big.py "lowering MOGGER_MAX_FILE_LINES blocks" MOGGER_MAX_FILE_LINES=500

gen s/edge.py 72 10 py   # 72 * 13 = 936? adjust below
head -n 800 "$SANDBOX/s/edge.py" > "$SANDBOX/s/edge800.py"
expect check-structure.sh 0 s/edge800.py "file of exactly 800 lines allowed (limit is exclusive)"
head -n 801 "$SANDBOX/s/edge.py" > "$SANDBOX/s/edge801.py"
expect check-structure.sh 2 s/edge801.py "file of 801 lines blocked"

gen s/bigjs.js 90 8 js
expect check-structure.sh 2 s/bigjs.js "big JS file blocked"
errhas 'move to a new module' "JS suggestion says which lines to move to a new module"
errhas 'lines [0-9]+-[0-9]+' "suggestion gives line ranges"

echo "== hook: check-structure.sh (false-positive guards)"
gen s/api.generated.ts 90 8 js
expect check-structure.sh 0 s/api.generated.ts "*.generated.* file skipped"
{ echo '// Code generated by protoc. DO NOT EDIT.'; cat "$SANDBOX/s/bigjs.js"; } > "$SANDBOX/s/svc.ts"
expect check-structure.sh 0 s/svc.ts "DO NOT EDIT header skipped"
gen s/vendor-lib.min.js 90 8 js
expect check-structure.sh 0 s/vendor-lib.min.js "minified name skipped"
awk 'BEGIN{for(i=0;i<900;i++) printf "x"; print ""; for(i=0;i<850;i++) print "var a" i "=1;"}' > "$SANDBOX/s/bundle.js"
{ awk 'BEGIN{for(i=0;i<1500;i++) printf "y"; print ""}'; cat "$SANDBOX/s/bundle.js"; } > "$SANDBOX/s/bundled.js"
expect check-structure.sh 0 s/bundled.js "minified content (1500-char line) skipped"
gen s/fixtures/users.ts 90 8 js
expect check-structure.sh 0 s/fixtures/users.ts "fixtures/ dir skipped"
gen s/countries-data.ts 90 8 js
expect check-structure.sh 0 s/countries-data.ts "*-data.ts skipped"
gen s/seed-db.js 90 8 js
expect check-structure.sh 0 s/seed-db.js "seed file skipped"
gen s/node_modules/pkg/index.js 90 8 js
expect check-structure.sh 0 s/node_modules/pkg/index.js "node_modules skipped"
awk 'BEGIN{for(i=0;i<900;i++) print "line " i}' > "$SANDBOX/s/notes.md"
expect check-structure.sh 0 s/notes.md "non-source (.md) ignored"
awk 'BEGIN{print "{"; for(i=0;i<900;i++) print "\"k" i "\": " i ","; print "\"z\":0}"}' > "$SANDBOX/s/package-lock.json"
expect check-structure.sh 0 s/package-lock.json "lock file ignored"
expect check-structure.sh 0 s/does-not-exist.py "missing file fails open"
printf 'not json' | bash "$H/check-structure.sh" >/dev/null 2>&1; [ $? -eq 0 ] && pass "bad JSON input fails open" || fail "bad JSON input fails open"

echo "== hook: check-structure.sh (shrinking an oversized file is allowed)"
mkdir -p g && cd g && git init -q . 2>/dev/null
git config user.email t@t; git config user.name t
cd "$SANDBOX"
gen g/big.py 90 8 py
( cd g && git add big.py && git commit -q -m init 2>/dev/null )
head -n 850 "$SANDBOX/g/big.py" > "$SANDBOX/g/tmp.py" && mv "$SANDBOX/g/tmp.py" "$SANDBOX/g/big.py"
expect check-structure.sh 0 g/big.py "write that shrinks an over-limit file (vs git HEAD) allowed"
{ cat "$SANDBOX/g/big.py"; cat "$SANDBOX/g/big.py"; } > "$SANDBOX/g/tmp.py" && mv "$SANDBOX/g/tmp.py" "$SANDBOX/g/big.py"
expect check-structure.sh 2 g/big.py "write that grows an over-limit file still blocked"

echo "== hook: check-structure.sh (copy-paste blocks)"
BLOCK='  const total = items.reduce((sum, item) => sum + item.price * item.qty, 0);
  const discount = total > 100 ? total * 0.1 : 0;
  const shipping = total > 50 ? 0 : 4.99;
  const taxable = total - discount;
  const tax = Math.round(taxable * 0.0825 * 100) / 100;
  const grand = taxable + tax + shipping;
  logger.info("computed order totals", { total, discount, shipping, tax });
  await saveTotals(orderId, { total, discount, shipping, tax, grand });
  emitEvent("order.totals", { orderId, grand });
  return { total, discount, shipping, tax, grand };'
w d/cart.js "async function cartTotals(orderId, items) {
$BLOCK
}"
expect check-structure.sh 0 d/cart.js "single copy of a block allowed"
w d/cart2.js "async function cartTotals(orderId, items) {
$BLOCK
}
async function invoiceTotals(orderId, items) {
$BLOCK
}"
TOOL=Edit NEW="async function invoiceTotals(orderId, items) {
$BLOCK
}" OLD="// TODO invoice" expect check-structure.sh 2 d/cart2.js "Edit that pastes an existing 10-line block is blocked"
errhas 'COPY-PASTE.*line [0-9]+.*line [0-9]+' "message names both locations"
TOOL=Write expect check-structure.sh 2 d/cart2.js "Write of a file containing a duplicated block is blocked"
TOOL=Edit NEW="function tweak() {
  const alpha = computeAlpha(input, config);
  return alpha;
}" OLD="// tweak" expect check-structure.sh 0 d/cart2.js "Edit adding a small distinct function allowed"
# pre-existing duplicate + unrelated edit (old_string contains the same block)
TOOL=Edit NEW="async function invoiceTotals(orderId, items) {
$BLOCK
  // changed
}" OLD="async function invoiceTotals(orderId, items) {
$BLOCK
}" expect check-structure.sh 0 d/cart2.js "editing around an already-duplicated block is not blocked"
w d/small-dup.js "function a() {
  const x = 1;
  const y = 2;
  return x + y;
}
function b() {
  const x = 1;
  const y = 2;
  return x + y;
}"
TOOL=Write expect check-structure.sh 0 d/small-dup.js "duplicate of only 4 lines allowed"
w d/imports.js "import a from './a';
import b from './b';
import c from './c';
import d from './d';
import e from './e';
import f from './f';
import g from './g';
import h from './h';
import i from './i';
import j from './j';
import k from './k';
import l from './l';
import a2 from './a';
import b2 from './b';
import c2 from './c';
import d2 from './d';
import e2 from './e';
import f2 from './f';
import g2 from './g';
import h2 from './h';
import i2 from './i';
import j2 from './j';
import k2 from './k';
import l2 from './l';"
TOOL=Write expect check-structure.sh 0 d/imports.js "repeated import lines are not a copy-paste finding"
awk 'BEGIN{for(r=0;r<2;r++) for(i=1;i<=12;i++) print "  // explanatory comment number " i " about this code"; print "x()"}' > "$SANDBOX/d/comments.js"
TOOL=Write expect check-structure.sh 0 d/comments.js "duplicated comment-only lines allowed"
awk 'BEGIN{for(r=0;r<2;r++) for(i=1;i<=12;i++) print "  }"}' > "$SANDBOX/d/braces.js"
TOOL=Write expect check-structure.sh 0 d/braces.js "duplicated trivial brace lines allowed"

# =====================================================================
echo "== hook: check-resilience.sh"
w r/a.js 'try { risky(); } catch (e) {}'
expect check-resilience.sh 2 r/a.js "empty catch (e) {} blocked"
errhas 'a.js:1' "message cites file:line"
errhas 'ignore:' "message explains the // ignore: escape"
w r/b.js 'try {
  risky();
} catch (err) {
}'
expect check-resilience.sh 2 r/b.js "multi-line empty catch blocked"
w r/c.js 'fetchThing().catch(() => {});'
expect check-resilience.sh 2 r/c.js ".catch(() => {}) blocked"
w r/c2.js 'fetchThing().catch(e => {});'
expect check-resilience.sh 2 r/c2.js ".catch(e => {}) blocked"
w r/d.ts 'try { risky(); } catch {}'
expect check-resilience.sh 2 r/d.ts "TS optional-binding empty catch {} blocked"
w r/e.js 'try { risky(); } catch (e) { console.error("risky failed", e); }'
expect check-resilience.sh 0 r/e.js "catch that logs allowed"
w r/f.js 'try { risky(); } catch (e) {} // ignore: cache is best-effort'
expect check-resilience.sh 0 r/f.js "documented // ignore: reason on same line allowed"
w r/g.js '// ignore: analytics must never break checkout
try { track(); } catch (e) {}'
expect check-resilience.sh 0 r/g.js "documented // ignore: reason on previous line allowed"
w r/h.js 'try {
  risky();
} catch (e) {
  // ignore: file may not exist yet
}'
expect check-resilience.sh 0 r/h.js "comment inside catch body allowed"
w r/i.js 'try { risky(); } catch (e) { throw e; }'
expect check-resilience.sh 0 r/i.js "catch that rethrows allowed"
w r/j.js 'p.catch((e) => { logger.error(e); });'
expect check-resilience.sh 0 r/j.js ".catch with a body allowed"
w r/k.py 'try:
    risky()
except:
    pass'
expect check-resilience.sh 2 r/k.py "python bare except: pass blocked"
w r/l.py 'try:
    risky()
except Exception: pass'
expect check-resilience.sh 2 r/l.py "python except Exception: pass blocked"
w r/l2.py 'try:
    risky()
except Exception as e:
    pass'
expect check-resilience.sh 2 r/l2.py "python except Exception as e: + pass blocked"
w r/m.py 'try:
    risky()
except KeyError:
    pass'
expect check-resilience.sh 0 r/m.py "python narrow except KeyError: pass allowed"
w r/n.py 'try:
    risky()
except Exception:
    logger.exception("risky failed")'
expect check-resilience.sh 0 r/n.py "python except that logs allowed"
w r/o.py 'try:
    risky()
except Exception:  # ignore: telemetry is best-effort
    pass'
expect check-resilience.sh 0 r/o.py "python documented # ignore: allowed"
w r/o2.py 'try:
    risky()
except Exception:
    # ignore: optional dependency
    pass'
expect check-resilience.sh 0 r/o2.py "python # ignore: comment before pass allowed"
w r/x.test.js 'try { risky(); } catch (e) {}'
expect check-resilience.sh 0 r/x.test.js "test file skipped"
w r/node_modules/p/i.js 'try { risky(); } catch (e) {}'
expect check-resilience.sh 0 r/node_modules/p/i.js "node_modules skipped"
w r/a.min.js 'try{x()}catch(e){}'
expect check-resilience.sh 0 r/a.min.js "minified file skipped"
w r/readme.md 'try { risky(); } catch (e) {}'
expect check-resilience.sh 0 r/readme.md "non-source file ignored"
expect check-resilience.sh 0 r/a.js "MOGGER_CHECK_RESILIENCE=off disables" MOGGER_CHECK_RESILIENCE=off
gen r/big.js 30 5 js
echo 'try { risky(); } catch (e) { log(e); }' >> "$SANDBOX/r/big.js"
TOOL=Edit NEW="try { risky(); } catch (e) { log(e); }" OLD="x" expect check-resilience.sh 0 r/big.js "Edit only checks new text (clean edit in file with no swallow)"
w r/legacy.js 'try { old(); } catch (e) {}
function fresh() { return 1; }'
TOOL=Edit NEW='function fresh() { return 1; }' OLD='function fresh() { return 0; }' expect check-resilience.sh 0 r/legacy.js "Edit ignores pre-existing swallow outside the edit"
TOOL=Edit NEW='try { a(); } catch (e) {}' OLD='a();' expect check-resilience.sh 2 r/legacy.js "Edit that adds an empty catch blocked"
expect check-resilience.sh 0 r/nope.js "missing file fails open"

# =====================================================================
echo "== check: structure.sh"
mkdir -p p1/src && cd p1
gen src/mid.py 60 9 py; gen src/huge.py 100 10 py; w src/tiny.py 'x = 1'
cd "$SANDBOX"
BEFORE=$(cd p1 && find . -type f | sort | xargs cksum | cksum)
run structure.sh p1
has '^WARN\|struct-file-size\|src/mid.py:1 has [0-9]+ lines' "500+ line file is a WARN with count"
has '^FAIL\|struct-file-size\|src/huge.py:1 has [0-9]+ lines' "1000+ line file is a FAIL with count"
hasnt 'struct-file-size\|src/tiny.py' "tiny file not reported"
contract structure.sh; rcz "structure.sh exits 0"
AFTER=$(cd p1 && find . -type f | sort | xargs cksum | cksum)
[ "$BEFORE" = "$AFTER" ] && pass "structure.sh does not modify the project" || fail "structure.sh modified the project"

mkdir -p p2/src && cd p2
{ echo 'export function bigOne(a) {'; for i in $(seq 1 100); do echo "  const v$i = a + $i;"; done; echo '  return v1;'; echo '}'; echo 'export function smallOne(a) {'; echo '  return a;'; echo '}'; } > src/f.js
{ echo 'def long_py(a):'; for i in $(seq 1 95); do echo "    v$i = a + $i"; done; echo '    return v1'; echo; echo 'def short_py(a):'; echo '    return a'; } > src/g.py
{ echo 'const Big = () => {'; for i in $(seq 1 90); do echo "  const p$i = $i;"; done; echo '  return p1;'; echo '};'; } > src/h.ts
cd "$SANDBOX"
run structure.sh p2
has '^WARN\|struct-func-size\|src/f.js:1: bigOne is 10[0-9] lines' "long JS function flagged with file:line"
has '^WARN\|struct-func-size\|src/g.py:1: long_py is' "long Python function flagged"
has '^WARN\|struct-func-size\|src/h.ts:1: Big is' "long arrow-function component flagged"
hasnt 'smallOne|short_py' "short functions not flagged"
has 'struct-func-size.*heuristic' "function-size finding is labelled heuristic"
contract structure.sh

mkdir -p p3/a p3/b && cd p3
BLK=$(for i in $(seq 1 12); do echo "  const step_$i = compute_something_long_name(input_$i, options.flag_$i);"; done)
w a/one.js "function one(input) {
$BLK
}"
w b/two.js "function two(input) {
$BLK
}"
w b/other.js "function other() {
  return 42;
}"
cd "$SANDBOX"
run structure.sh p3
has '^WARN\|struct-duplicates\|.*(a/one.js|b/two.js):[0-9]+ duplicates (a/one.js|b/two.js):[0-9]+ \(1[0-9] lines\)' "duplicate block reported with both file:line locations"
hasnt 'other.js.*duplicates|duplicates.*other.js' "unrelated file not implicated"

mkdir -p p4/src && cd p4
w src/a.js "import x from 'x';
import y from 'y';
import z from 'z';
import q from 'q';
import r from 'r';
import s from 's';
import t from 't';
import u from 'u';
import v from 'v';"
w src/b.js "import x from 'x';
import y from 'y';
import z from 'z';
import q from 'q';
import r from 'r';
import s from 's';
import t from 't';
import u from 'u';
import v from 'v';"
w src/c.js "function c1(a) { return a + 1; }
function c2(a) { return a * 2; }"
w src/d.js "function d1(a) { return a - 1; }
function d2(a) { return a / 2; }"
cd "$SANDBOX"
run structure.sh p4
has '^PASS\|struct-duplicates' "identical import headers are not copy-paste"
has '^PASS\|struct-func-size' "no long functions in small project"
has '^PASS\|struct-nesting' "PASS line for nesting group"

mkdir -p p5/src p5/node_modules/x p5/dist && cd p5
gen src/keep.js 5 5 js
cp "$SANDBOX/s/bigjs.js" node_modules/x/huge.js; cp "$SANDBOX/s/bigjs.js" dist/huge.js
{ echo '// @generated by tool'; cat "$SANDBOX/s/bigjs.js"; } > src/gen_api.js
gen src/api.generated.ts 100 10 js; cp "$SANDBOX/s/bundled.js" src/vendor.bundle.js
cd "$SANDBOX"
run structure.sh p5
hasnt 'node_modules|dist/' "node_modules and dist skipped"
hasnt 'gen_api|api.generated|vendor.bundle|bundled' "generated and minified files skipped"
has '^PASS\|struct-file-size' "size group PASS when only skipped files are large"

mkdir -p p6/src && cd p6
w src/x.test.js "$(cat "$SANDBOX/s/bigjs.js")"
gen src/y.js 4 4 js
cd "$SANDBOX"
run structure.sh p6
has '^FAIL\|struct-file-size\|src/x.test.js' "size check includes test files"
hasnt 'struct-func-size.*x.test' "function-size ignores test files"

mkdir -p p7/wide && cd p7
for i in $(seq 1 45); do w "wide/f$i.js" "module.exports = $i;"; done
cd "$SANDBOX"
run structure.sh p7
has '^WARN\|struct-flat-folder\|wide/: 45 source files' "folder with 45 flat files flagged"

mkdir -p p8 && cd p8
for i in 1 2 3 4 5 6; do w "mod$i.py" "x = $i"; done
cd "$SANDBOX"
run structure.sh p8
has '^WARN\|struct-separation\|all 6 source files live in the repo root.*heuristic' "all source in repo root flagged as heuristic"
mkdir -p p9/src && cd p9
for i in 1 2 3 4 5 6; do w "src/mod$i.py" "x = $i"; done; w main.py 'x = 0'
cd "$SANDBOX"
run structure.sh p9
has '^PASS\|struct-separation' "source in src/ folder passes separation"

mkdir -p p10 && cd p10
{ echo 'def f(a):'; echo '    if a:'; echo '        for x in a:'; echo '            if x:'; echo '                while x:'; echo '                    try:'; echo '                        if x > 1:'; echo '                            for y in x:'; echo '                                print(y)'; echo '                                break'; echo '                    finally:'; echo '                        pass'; } > deep.py
cd "$SANDBOX"
run structure.sh p10
has '^WARN\|struct-nesting\|deep.py:[0-9]+: nesting depth [0-9]+ \(heuristic' "deep nesting flagged (heuristic)"

mkdir -p empty && run structure.sh empty
has '^SKIP\|struct-file-size\|no source files' "empty project: SKIP with reason"
contract "structure.sh (empty)"
OUT=$(cd "$SANDBOX" && bash "$C/structure.sh" /nonexistent-dir-xyz 2>/dev/null); ORC=$?
rcz "structure.sh exits 0 for a missing directory"

# ---- performance: duplicate finder on a synthetic 300-file repo
mkdir -p perf/src && cd perf
for f in $(seq 1 300); do
  fn=$(printf "src/mod%03d.js" "$f")
  awk -v f="$f" 'BEGIN { for (i=1;i<=160;i++) { if (i%40==1) printf "function unit_%d_%d(input) {\n", f, i
    printf "  const local_%d_%d = compute(input, %d) + shared_helper_%d(%d);\n", f, i, i*f, i%9, f
    if (i%40==0) print "}" } }' > "$fn"
done
cd "$SANDBOX"
T0=$(date +%s)
run structure.sh perf
T1=$(date +%s); EL=$((T1-T0))
if [ "$EL" -lt 20 ]; then pass "structure.sh on a 300-file repo finished in ${EL}s (< 20s)"; else fail "structure.sh too slow: ${EL}s"; fi
has '^(PASS|WARN)\|struct-duplicates' "duplicate finder produced a verdict on the 300-file repo"

# =====================================================================
echo "== check: resilience.sh"
mkdir -p q1/src && cd q1
cat > src/app.js <<'EOF'
const express = require('express');
const app = express();
async function a() {
  try { risky(); } catch (e) {}
  try {
    risky();
  } catch (e) {
  }
  try { risky(); } catch (e) { /* ignore: best effort */ }
  try { risky(); } catch (e) { console.error(e); }
  p.catch(() => {});
  p.catch(() => {}); // ignore: fire and forget
}
app.get('/users', async (req, res) => {
  const users = await prisma.user.findMany();
  for (const u of users) {
    const o = await db.order.findMany({ where: { userId: u.id } });
  }
  const r = await fetch('http://x');
  const r2 = await fetch('http://x', { signal: AbortSignal.timeout(5000) });
  const t = users.map(x => x.id * 2);
  res.json(users);
});
console.log('hi');
EOF
cat > src/a.py <<'EOF'
import requests
def f(cur, users):
    try:
        x()
    except:
        pass
    try:
        x()
    except ValueError:
        # ignore: optional
        pass
    for u in users:
        cur.execute("select 1")
    requests.get("http://a")
    requests.get("http://a", timeout=3)
    rows = cur.execute("SELECT * FROM users")
    ok = cur.execute("SELECT * FROM users LIMIT 10")
    total = 0
    for u in users:
        total += u.price * 2
EOF
cd "$SANDBOX"
BEFORE=$(cd q1 && find . -type f | sort | xargs cksum | cksum)
run resilience.sh q1
has '^WARN\|res-empty-catch\|src/app.js:4:' "empty catch one-liner flagged with line"
has '^WARN\|res-empty-catch\|src/app.js:7:' "multi-line empty catch flagged at the catch line"
hasnt 'res-empty-catch\|src/app.js:(9|10|12):' "commented/logged/ignore-documented catches not flagged"
has 'res-empty-catch\|src/app.js:11: .catch' ".catch(() => {}) flagged"
has '^WARN\|res-empty-catch\|src/a.py:5:' "python except: pass flagged"
hasnt 'res-empty-catch\|src/a.py:(9|10|11):' "python documented except not flagged"
has '^WARN\|res-timeout\|src/app.js:19:' "fetch with no timeout flagged"
hasnt 'res-timeout\|src/app.js:20:' "fetch with AbortSignal.timeout not flagged (adjacent call does not leak)"
has '^WARN\|res-timeout\|src/a.py:14:' "requests.get without timeout flagged"
hasnt 'res-timeout\|src/a.py:15:' "requests.get with timeout= not flagged"
has '^WARN\|res-async-handler\|src/app.js:14:' "async route handler without try/catch flagged"
has '^WARN\|res-unbounded\|src/app.js:15:.*heuristic' "findMany() without take flagged (heuristic)"
has '^WARN\|res-unbounded\|src/a.py:16:' "SELECT * without LIMIT flagged"
hasnt 'res-unbounded\|src/a.py:17:' "SELECT * ... LIMIT not flagged"
has '^WARN\|res-n-plus-1\|src/app.js:17:.*loop that starts at line 16' "await DB call in for loop flagged (N+1)"
has '^WARN\|res-n-plus-1\|src/a.py:13:' "python cursor.execute in loop flagged"
hasnt 'res-n-plus-1\|src/app.js:(20|21|22|23):' "pure map computation not flagged as N+1"
hasnt 'res-n-plus-1\|src/a.py:(2[0-9]):' "pure computation loop not flagged as N+1"
has '^WARN\|res-logging\|.*console.log.*heuristic' "console.log-only logging flagged (heuristic)"
has '^WARN\|res-error-tracking\|' "no error-tracking SDK flagged"
has '^WARN\|res-health\|' "server without health endpoint flagged"
contract resilience.sh; rcz "resilience.sh exits 0"
AFTER=$(cd q1 && find . -type f | sort | xargs cksum | cksum)
[ "$BEFORE" = "$AFTER" ] && pass "resilience.sh does not modify the project" || fail "resilience.sh modified the project"

mkdir -p q2/src && cd q2
cat > src/app.js <<'EOF'
const express = require('express');
const pino = require('pino');
const Sentry = require('@sentry/node');
const logger = pino();
const axios = require('axios');
const app = express();
app.get('/health', (req, res) => res.send('ok'));
app.get('/items', async (req, res) => {
  try {
    const items = await prisma.item.findMany({ take: 20, skip: 0 });
    const r = await axios.get('http://x', { timeout: 3000 });
    res.json(items);
  } catch (e) {
    logger.error({ err: e }, 'items failed');
    res.status(500).end();
  }
});
app.use((err, req, res, next) => { res.status(500).end(); });
EOF
cd "$SANDBOX"
run resilience.sh q2
hasnt '^WARN' "well-behaved project: no WARN at all"
has '^PASS\|res-logging\|.*pino' "logging library recognised"
has '^PASS\|res-error-tracking\|' "Sentry recognised"
has '^PASS\|res-health\|.*app.js:7' "/health endpoint recognised"
has '^PASS\|res-timeout' "axios with timeout passes"
has '^PASS\|res-unbounded' "findMany with take passes"
has '^PASS\|res-async-handler' "error middleware / try-catch passes"

mkdir -p q3 && cd q3
cat > s.js <<'EOF'
const app = require('express')();
app.post('/x', async (req, res) => {
  const data = await load();
  res.json(data);
});
app.use((err, req, res, next) => { res.status(500).end(); });
EOF
cd "$SANDBOX"
run resilience.sh q3
has '^PASS\|res-async-handler\|.*error middleware' "project-level error middleware satisfies async-handler check"

mkdir -p q4 && cd q4
cat > c.js <<'EOF'
const axios = require('axios');
const client = axios.create({
  baseURL: 'http://x',
  timeout: 5000,
});
async function go() { return client.get('/a'); }
async function go2() { return axios.get('/b'); }
EOF
cat > g.go <<'EOF'
package main
func f() {
	resp, err := http.Get("http://x")
	_ = err
	if err != nil {
	}
}
EOF
cd "$SANDBOX"
run resilience.sh q4
has '^WARN\|res-empty-catch\|g.go:4' "Go _ = err flagged"
has '^WARN\|res-empty-catch\|g.go:[56]' "Go empty if err != nil flagged"
has '^WARN\|res-timeout\|g.go:3' "Go http.Get without timeout flagged"
hasnt 'res-timeout\|c.js' "axios.create with timeout counts as defaults"

mkdir -p q5 && cd q5
w lib.js 'export const add = (a, b) => a + b;'
cd "$SANDBOX"
run resilience.sh q5
has '^SKIP\|res-health\|no HTTP server' "no server code: health check SKIP with reason"
mkdir -p q6 && run resilience.sh q6
has '^SKIP\|res-empty-catch\|no JS/TS/Python/Go' "no source: SKIP with reason"
contract "resilience.sh (empty)"

# =====================================================================
echo "== check: database.sh"
mkdir -p d1/supabase/migrations d1/prisma d1/app && cd d1
cat > supabase/migrations/001.sql <<'EOF'
create table public.users (
  id uuid primary key default gen_random_uuid(),
  email text,
  username text unique not null
);
create table posts (
  id serial primary key,
  user_id uuid references users(id),
  title text
);
create table tags (
  name text,
  post_id int,
  constraint fk foreign key (post_id) references posts(id)
);
create table good (
  id int primary key,
  owner_id int not null references users(id)
);
create index idx_good_owner on good(owner_id);
alter table good enable row level security;
alter table users enable row level security;
EOF
cat > prisma/schema.prisma <<'EOF'
datasource db { provider = "postgresql" url = env("U") }
model User {
  id Int @id
  email String
  posts Post[]
}
model Post {
  id Int @id
  authorId Int
  author User @relation(fields: [authorId], references: [id])
}
model Bad {
  name String
}
model Ok {
  id Int @id
  ownerId Int
  owner User @relation(fields: [ownerId], references: [id])
  @@index([ownerId])
}
EOF
cat > app/models.py <<'EOF'
from django.db import models
class A(models.Model):
    email = models.EmailField()
    owner = models.ForeignKey(User, on_delete=models.CASCADE)
class B(models.Model):
    email = models.EmailField(unique=True)
    o = models.ForeignKey(User, on_delete=models.CASCADE, db_index=False)
class S(Base):
    __tablename__ = "s"
    id = Column(Integer, primary_key=True)
    u = Column(Integer, ForeignKey("u.id"))
    username = Column(String)
class NoPk(Base):
    __tablename__ = "n"
    x = Column(String)
class Dto(BaseModel):
    email: str
EOF
cd "$SANDBOX"
BEFORE=$(cd d1 && find . -type f | sort | xargs cksum | cksum)
run database.sh d1
has "^FAIL\|db-primary-key\|supabase/migrations/001.sql:11: table 'tags' has no PRIMARY KEY" "SQL table without primary key FAILs with file:line"
hasnt "db-primary-key.*table '(users|posts|good)'" "tables with PRIMARY KEY (inline) not flagged"
has "^FAIL\|db-primary-key\|prisma/schema.prisma:12: Prisma model 'Bad'" "Prisma model without @id FAILs"
has "^FAIL\|db-primary-key\|app/models.py:13: SQLAlchemy model 'NoPk'" "SQLAlchemy model without primary key FAILs"
has "^WARN\|db-fk-index\|supabase/migrations/001.sql:6: .*'posts.user_id'" "unindexed inline REFERENCES column flagged"
has "^WARN\|db-fk-index\|supabase/migrations/001.sql:11: .*'tags.post_id'" "unindexed table-level FOREIGN KEY flagged"
hasnt "db-fk-index.*'good.owner_id'" "FK with CREATE INDEX not flagged"
has "^WARN\|db-fk-index\|prisma/schema.prisma:10: .*Post.authorId" "Prisma relation without @@index flagged"
hasnt "db-fk-index.*Ok.ownerId" "Prisma relation with @@index not flagged"
has "^WARN\|db-fk-index\|app/models.py:7: .*B.o" "Django FK with db_index=False flagged"
hasnt "db-fk-index.*A.owner" "Django FK (auto-indexed) not flagged"
has "^WARN\|db-fk-index\|app/models.py:11: .*S.u" "SQLAlchemy FK without index flagged"
has "^WARN\|db-unique\|supabase/migrations/001.sql:1: .*'users.email'.*heuristic" "email without UNIQUE flagged (heuristic)"
hasnt "db-unique.*'users.username'" "username unique not null not flagged"
has "^WARN\|db-unique\|prisma/schema.prisma:4: .*User.email" "Prisma email without @unique flagged"
has "^WARN\|db-unique\|app/models.py:3: .*A.email" "Django email without unique flagged"
hasnt "db-unique.*B.email" "Django email unique=True not flagged"
hasnt "db-unique.*Dto|db-unique.*models.py:1[78]" "pydantic BaseModel email not treated as a table"
has "^WARN\|db-rls\|supabase/migrations/001.sql:6: .*'posts'" "Supabase table without RLS flagged as db-rls"
hasnt "db-rls.*'(good|users)'" "Supabase tables with ENABLE ROW LEVEL SECURITY not flagged"
has "^PASS\|db-migrations\|" "migrations present PASS"
has "^WARN\|db-backup\|no backup plan documented" "no backup plan -> WARN"
contract database.sh; rcz "database.sh exits 0"
AFTER=$(cd d1 && find . -type f | sort | xargs cksum | cksum)
[ "$BEFORE" = "$AFTER" ] && pass "database.sh does not modify the project" || fail "database.sh modified the project"

mkdir -p d2/db/migrations && cd d2
cat > db/migrations/001_init.sql <<'EOF'
CREATE TABLE accounts (
  id BIGSERIAL PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  name TEXT
);
CREATE TABLE orders (
  id BIGSERIAL PRIMARY KEY,
  account_id BIGINT NOT NULL REFERENCES accounts(id)
);
CREATE INDEX orders_account_idx ON orders (account_id);
EOF
w README.md '## Ops
Nightly pg_dump to S3; restore tested monthly.'
cd "$SANDBOX"
run database.sh d2
hasnt '^(WARN|FAIL)\|db-(primary-key|fk-index|unique|migrations)' "well-designed schema: no design findings"
has '^PASS\|db-primary-key' "PK group PASS"
has '^PASS\|db-backup\|.*README.md' "pg_dump mention in docs satisfies backup check"
has '^SKIP\|db-rls\|not a Supabase' "RLS group SKIP outside Supabase (with reason)"

mkdir -p d3 && cd d3
w package.json '{"dependencies":{"prisma":"5","@prisma/client":"5"}}'
w src/db.js 'const { PrismaClient } = require("@prisma/client");'
cd "$SANDBOX"
run database.sh d3
has '^WARN\|db-migrations\|.*schema lives only in app code' "DB used but no migrations dir -> WARN"
has '^SKIP\|db-primary-key\|no SQL' "no schema files: PK group SKIP with reason"

mkdir -p d4 && cd d4
w app.js 'console.log("no database here")'
cd "$SANDBOX"
run database.sh d4
has '^SKIP\|db-migrations\|no database usage' "no database: migrations SKIP"
has '^SKIP\|db-backup\|no database usage' "no database: backup SKIP"

mkdir -p d5 && cd d5
cat > schema.ts <<'EOF'
import { pgTable, serial, text, integer, uniqueIndex } from 'drizzle-orm/pg-core';
export const users = pgTable('users', {
  id: serial('id').primaryKey(),
  email: text('email'),
});
export const posts = pgTable('posts', {
  id: serial('id').primaryKey(),
  authorId: integer('author_id').references(() => users.id),
});
export const noPk = pgTable('no_pk', {
  name: text('name'),
});
EOF
cat > entity.ts <<'EOF'
@Entity()
export class Photo {
  @PrimaryGeneratedColumn()
  id: number;
  @Column({ unique: true })
  email: string;
  @ManyToOne(() => User)
  owner: User;
}
EOF
cd "$SANDBOX"
run database.sh d5
has "^FAIL\|db-primary-key\|schema.ts:[0-9]+: Drizzle table 'no_pk'" "Drizzle table without primaryKey FAILs"
hasnt "db-primary-key.*'(users|posts)'" "Drizzle tables with primaryKey() not flagged"
has "^WARN\|db-fk-index\|schema.ts:[0-9]+: Drizzle table 'posts'" "Drizzle .references() without index() flagged"
has "^WARN\|db-unique\|schema.ts:[0-9]+: field 'users.email'" "Drizzle email without unique flagged"
has "^WARN\|db-fk-index\|entity.ts:[0-9]+: TypeORM entity 'Photo'" "TypeORM ManyToOne without @Index flagged"
hasnt "db-unique.*Photo" "TypeORM email with unique:true not flagged"
hasnt "db-primary-key.*Photo" "TypeORM entity with @PrimaryGeneratedColumn not flagged"

# =====================================================================
echo "== check: cost-risk.sh"
mkdir -p k1/src && cd k1
cat > src/a.js <<'EOF'
const OpenAI = require('openai');
const client = new OpenAI();
app.post('/chat', async (req, res) => {
  const r = await client.chat.completions.create({ model: 'x', messages: [] });
  res.json(r);
});
async function batch(items) {
  for (const i of items) {
    await client.chat.completions.create({ model: 'x', max_tokens: 10 });
  }
  const t = items.map(i => i + 1);
  while (true) {
    await client.responses.create({ model: 'y' });
  }
}
function again(n) {
  client.embeddings.create({ input: n });
  return again(n + 1);
}
retry(() => call());
const k = process.env.NEXT_PUBLIC_OPENAI_API_KEY;
EOF
cat > src/b.py <<'EOF'
import anthropic
def go(xs, c):
    for x in xs:
        c.messages.create(model="m", max_tokens=5, messages=[])
    while True:
        try:
            c.messages.create(model="m", messages=[])
            break
        except Exception:
            pass
    total = 0
    for x in xs:
        total += x
EOF
cat > src/nomax.js <<'EOF'
const Anthropic = require('@anthropic-ai/sdk');
async function ask(c) { return c.messages.create({ model: 'm', messages: [] }); }
EOF
cat > src/ok.js <<'EOF'
const OpenAI = require('openai');
async function ask(c) { return c.chat.completions.create({ model: 'm', max_tokens: 100, messages: [] }); }
EOF
cd "$SANDBOX"
BEFORE=$(cd k1 && find . -type f | sort | xargs cksum | cksum)
run cost-risk.sh k1
has '^WARN\|cost-loop\|src/a.js:9:.*loop that starts at line 8' "paid call in for loop flagged with line"
has '^WARN\|cost-loop\|src/b.py:4:' "python paid call in loop flagged"
hasnt 'cost-loop\|src/a.js:1[0-1]' "pure map computation not flagged"
hasnt 'cost-loop\|src/b.py:(1[2-9])' "pure summing loop not flagged"
has '^FAIL\|cost-unbounded-loop\|src/a.js:13:.*infinite loop' "paid call in while(true) with no exit -> FAIL"
has '^WARN\|cost-unbounded-loop\|src/b.py:7:.*infinite loop' "while True with break -> WARN only"
has "^WARN\|cost-unbounded-loop\|src/a.js:[0-9]+: function 'again'.*calls itself" "recursion around a paid call flagged (heuristic)"
has '^WARN\|cost-max-tokens\|src/nomax.js:2:' "LLM call in file with no max tokens flagged"
hasnt 'cost-max-tokens\|src/ok.js' "LLM call with max_tokens not flagged"
has '^WARN\|cost-retry\|src/a.js:20:' "retry() with no max attempts flagged"
has '^WARN\|cost-rate-limit\|route handler at src/a.js:4.*no rate limiter' "public route with paid call and no limiter flagged"
has '^WARN\|cost-client-key\|src/a.js:21:.*report only' "NEXT_PUBLIC_ paid key flagged (report only, no FAIL)"
hasnt '^FAIL\|cost-client-key' "client-key finding never FAILs (security.sh owns that)"
has '^WARN\|cost-spend-limit\|.*Manual step.*CANNOT be verified from code' "spend-limit reminder states it is manual"
contract cost-risk.sh; rcz "cost-risk.sh exits 0"
AFTER=$(cd k1 && find . -type f | sort | xargs cksum | cksum)
[ "$BEFORE" = "$AFTER" ] && pass "cost-risk.sh does not modify the project" || fail "cost-risk.sh modified the project"

mkdir -p k2/src && cd k2
cat > src/safe.js <<'EOF'
const OpenAI = require('openai');
const rateLimit = require('express-rate-limit');
app.use(rateLimit({ windowMs: 60000, max: 10 }));
app.post('/chat', async (req, res) => {
  const r = await client.chat.completions.create({ model: 'x', max_tokens: 200, messages: [] });
  res.json(r);
});
async function batch(items) {
  const limited = items.slice(0, 10);
  const out = [];
  for (const i of limited) { out.push(i * 2); }
  await withRetry(() => call(), { maxRetries: 3, backoff: 'exponential' });
  return out;
}
EOF
cd "$SANDBOX"
run cost-risk.sh k2
has '^PASS\|cost-rate-limit\|.*express-rate-limit|^PASS\|cost-rate-limit' "rate limiter present -> PASS"
has '^PASS\|cost-loop' "loop with only pure computation -> PASS"
has '^PASS\|cost-max-tokens' "max_tokens set -> PASS"
has '^PASS\|cost-client-key' "no client-side keys -> PASS"
hasnt '^(WARN|FAIL)\|cost-(loop|unbounded-loop|max-tokens|retry|rate-limit)' "safe project: no cost findings"

mkdir -p k3/src && cd k3
cat > src/db.js <<'EOF'
async function seed(rows) {
  for (const r of rows) {
    await prisma.customers.create({ data: r });
    await db.emails.send_log.create({ data: r });
  }
}
EOF
cd "$SANDBOX"
run cost-risk.sh k3
has '^SKIP\|cost-loop\|no paid API' "DB create() in a loop is not a paid API call"
has '^PASS\|cost-spend-limit\|.*manual step' "no paid API: spend-limit line is a PASS reminder"
mkdir -p k4/src && cd k4
cat > src/pay.js <<'EOF'
const stripe = require('stripe')(process.env.KEY);
async function refundAll(ids) {
  for (const id of ids) {
    await stripe.refunds.create({ payment_intent: id });
  }
}
EOF
cat > .env.local <<'EOF'
NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY=pk_test_x
NEXT_PUBLIC_SENDGRID_KEY=SG.x
EOF
cd "$SANDBOX"
run cost-risk.sh k4
has '^WARN\|cost-loop\|src/pay.js:4:' "stripe refund in loop flagged"
has '^WARN\|cost-client-key\|\.env\.local:2:' "NEXT_PUBLIC_SENDGRID_KEY in .env flagged"
hasnt 'cost-client-key.*\.env\.local:1:' "publishable key not flagged"
mkdir -p k5 && run cost-risk.sh k5
has '^SKIP\|cost-loop\|no JS/TS/Python/Go' "no source: SKIP with reason"
contract "cost-risk.sh (empty)"

echo
echo "code-health: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
