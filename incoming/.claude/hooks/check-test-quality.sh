#!/usr/bin/env bash
# PostToolUse — matcher: Edit|Write
# Stops FAKE tests being written: tests that cannot fail. When the file just
# written is a test file, scan it and exit 2 (feedback to Claude) with an exact
# file:line list of HIGH-CONFIDENCE problems:
#   - a test/it body that is empty or contains no assertion at all
#   - tautologies: expect(true).toBe(true), assert True, assert 1 == 1,
#     expect(x).toBe(x) (same simple token), assertEqual(1, 1) ...
#   - focused tests committed: .only( / fdescribe / fit(  (silently skips the rest)
# WARN only (stderr + additionalContext, exit 0 - never blocks):
#   - skipped tests with no reason (.skip / xit / @pytest.mark.skip / t.Skip())
#   - HEURISTIC: a test whose only assertions are "mock was called" while the
#     file mocks its collaborators (proves the wiring, not the behaviour)
# Test files: test_*.py *_test.py *.test.{js,ts,jsx,tsx,mjs} *.spec.* *_test.go,
# and code files under tests/ test/ __tests__/.
# Conservative on purpose: a test that calls a helper defined in the same file
# (or imported from a helper/util/support module) or passes t to a helper is
# assumed to assert there. Anything the scanner cannot parse => no finding.
# Fails OPEN: no jq/python3, unreadable file, awk trouble => exit 0.
# Escape hatch: MOGGER_CHECK_TESTS=off
#
# Also usable as a library: MOGGER_TQ_SOURCE_ONLY=1 source this file, then
# call tq_init / tq_is_test_path / tq_scan_file (used by scripts/checks/tests-quality.sh).
# And directly:  check-test-quality.sh --scan FILE...  prints KIND|file|line|msg

tq_awk_prog() {
  cat <<'AWK'
# true when the text so far ends inside an open string literal (odd quote count)
function instr(pre,   t) {
  t = pre; if (gsub(/"/, "", t) % 2) return 1
  t = pre; if (gsub(SQ, "", t) % 2) return 1
  t = pre; if (gsub(/`/, "", t) % 2) return 1
  return 0
}
function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
function indent(s,   t) { t = s; gsub(/\t/, "    ", t); match(t, /^[[:space:]]*/); return RLENGTH }
function issimple(x) {
  if (x == "") return 0
  if (x ~ /^[[:alnum:]_.-]+$/) return 1
  if (x ~ /^"[^"]*"$/) return 1
  if (substr(x, 1, 1) == SQ && index(substr(x, 2), SQ) == length(x) - 1) return 1
  return 0
}
function mp(s, pos,   n, d, i, ch) {
  n = length(s); d = 0
  for (i = pos; i <= n; i++) {
    ch = substr(s, i, 1)
    if (ch == "(") d++
    else if (ch == ")") { d--; if (d == 0) return i }
  }
  return 0
}
function splitargs(s,   n, d, i, ch, cur, inq, k) {
  n = length(s); d = 0; k = 0; cur = ""; inq = ""
  for (i = 1; i <= n; i++) {
    ch = substr(s, i, 1)
    if (inq != "") { cur = cur ch; if (ch == inq) inq = ""; continue }
    if (ch == "\"" || ch == SQ) { inq = ch; cur = cur ch; continue }
    if (ch == "(" || ch == "[" || ch == "{") d++
    else if (ch == ")" || ch == "]" || ch == "}") d--
    if (ch == "," && d == 0) { k++; ARGS[k] = trim(cur); cur = ""; continue }
    cur = cur ch
  }
  k++; ARGS[k] = trim(cur)
  return k
}
function emit(kind, ln, msg) { print kind "|" F "|" ln "|" msg }
function short(s) { s = trim(s); if (length(s) > 70) s = substr(s, 1, 70) "..."; return s }
function cnt(s, re,   k) { k = 0; while (match(s, re)) { k++; s = substr(s, RSTART + RLENGTH) } return k }
function commentReason(i,   k) {
  for (k = i; k >= 1 && k >= i - 1; k--)
    if (raw[k] ~ /(\/\/|\/\*|#)[[:space:]]*[[:alnum:]]/) return 1
  return 0
}
# ---- line cleaning: cs = comments removed, strings kept; c = strings removed too
function cln(i,   s, p, q, p1, p3, d, t) {
  s = raw[i]
  ind[i] = indent(s)
  if (LG == "py") {
    if (intrip != "") {
      p = index(s, intrip)
      if (p == 0) { cs[i] = ""; c[i] = ""; return }
      s = substr(s, p + 3); intrip = ""
    }
    while (1) {
      p3 = index(s, "\"\"\""); p1 = index(s, SQ SQ SQ)
      if (p3 == 0 && p1 == 0) break
      if (p3 == 0 || (p1 > 0 && p1 < p3)) { d = SQ SQ SQ; p = p1 } else { d = "\"\"\""; p = p3 }
      q = index(substr(s, p + 3), d)
      if (q == 0) { intrip = d; s = substr(s, 1, p - 1) "\"\""; break }
      s = substr(s, 1, p - 1) "\"\"" substr(s, p + 3 + q + 2)
    }
    sub(/(^|[[:space:]])#.*$/, "", s)
  } else {
    if (inblk) {
      p = index(s, "*/")
      if (p == 0) { cs[i] = ""; c[i] = ""; return }
      s = substr(s, p + 2); inblk = 0
    }
    while ((p = index(s, "/*")) > 0) {
      q = index(substr(s, p + 2), "*/")
      if (q == 0) { s = substr(s, 1, p - 1); inblk = 1; break }
      s = substr(s, 1, p - 1) " " substr(s, p + q + 3)
    }
    sub(/(^|[[:space:]])\/\/.*$/, "", s)
  }
  cs[i] = s
  gsub(/"[^"]*"/, "\"\"", s)
  if (LG != "py") gsub(/`[^`]*`/, "\"\"", s)
  t = SQ "[^" SQ "]*" SQ
  gsub(t, "\"\"", s)
  c[i] = s
}
function addidents(s,   t) {
  while (match(s, /[[:alpha:]_][[:alnum:]_]*/)) {
    t = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
    if (t != "import" && t != "from" && t != "require" && t != "const" && t != "let" && t != "var" && t != "as" && t != "default" && t != "def" && t != "func" && t != "package")
      H[t] = 1
  }
}
function collect(i,   s, t, lr) {
  s = c[i]
  if (LG == "js") {
    if (match(s, /function[[:space:]]+[[:alpha:]_][[:alnum:]_]*/)) { t = substr(s, RSTART, RLENGTH); sub(/function[[:space:]]+/, "", t); H[t] = 1 }
    if (match(s, /(const|let|var)[[:space:]]+[[:alpha:]_][[:alnum:]_]*[[:space:]]*=[[:space:]]*(async[[:space:]]*)?(function|\(|[[:alpha:]_][[:alnum:]_]*[[:space:]]*=>)/)) {
      t = substr(s, RSTART, RLENGTH); sub(/^(const|let|var)[[:space:]]+/, "", t); sub(/[^[:alnum:]_].*$/, "", t); H[t] = 1
    }
  } else if (LG == "py") {
    if (match(s, /def[[:space:]]+[[:alpha:]_][[:alnum:]_]*/)) { t = substr(s, RSTART, RLENGTH); sub(/def[[:space:]]+/, "", t); if (t !~ /^test/) H[t] = 1 }
  } else {
    if (match(s, /^func[[:space:]]+[[:alpha:]_][[:alnum:]_]*/)) { t = substr(s, RSTART, RLENGTH); sub(/func[[:space:]]+/, "", t); if (t !~ /^Test/) H[t] = 1 }
  }
  lr = tolower(raw[i])
  if (raw[i] ~ /(import|require|from)/ && lr ~ /(helper|util|support|setup|fixture|common|shared|harness|scenario|conftest)/ && lr !~ /testing-library|@testing/) addidents(cs[i])
}
function delegates(body,   nm) {
  for (nm in H) if (body ~ ("(^|[^[:alnum:]_])" nm "[(.]")) return 1
  return 0
}
# ---- tautologies on a comment-stripped line
function taut(s, ln,   pre, rest, m, nm, inner, cl, after, a, b, pp, n, arg, r, p) {
  rest = s
  while (match(rest, /(expect|self[.]assert[[:alnum:]_]*|assert[[:alnum:]_.]*|require[.][[:alnum:]_]+)[[:space:]]*[(]/)) {
    m = RSTART
    nm = substr(rest, RSTART, RLENGTH); sub(/[[:space:]]*[(]$/, "", nm); sub(/^self[.]/, "", nm)
    pp = RSTART + RLENGTH - 1
    if (m > 1 && substr(rest, m - 1, 1) ~ /[[:alnum:]_]/) { rest = substr(rest, pp + 1); continue }
    pre = substr(s, 1, length(s) - length(rest) + m - 1)
    if (instr(pre)) { rest = substr(rest, pp + 1); continue }
    cl = mp(rest, pp)
    if (cl == 0) return
    inner = substr(rest, pp + 1, cl - pp - 1)
    after = substr(rest, cl + 1)
    rest = after
    if (nm == "expect") {
      a = trim(inner)
      if (match(after, /^[[:space:]]*[.](toBe|toEqual|toStrictEqual)[[:space:]]*[(]/)) {
        p = RLENGTH
        cl = mp(after, p)
        if (cl > 0) {
          b = trim(substr(after, p + 1, cl - p - 1))
          if (issimple(a) && a == b) emit("TAUT", ln, "tautology: expect(" a ") compared with itself - cannot fail")
        }
      } else if (match(after, /^[[:space:]]*[.]toBeTruthy[[:space:]]*[(][[:space:]]*[)]/)) {
        if (a == "true" || a == "1") emit("TAUT", ln, "tautology: expect(" a ").toBeTruthy() - cannot fail")
      } else if (match(after, /^[[:space:]]*[.]toBeFalsy[[:space:]]*[(][[:space:]]*[)]/)) {
        if (a == "false" || a == "0" || a == "null" || a == "undefined") emit("TAUT", ln, "tautology: expect(" a ").toBeFalsy() - cannot fail")
      }
    } else if (nm ~ /^(assert|assert[.]ok|assert[.]True|assert[.]isTrue|assertTrue|require[.]True|require[.]ok)$/) {
      n = splitargs(inner)
      arg = ""
      if (n == 1) arg = ARGS[1]
      else if (n == 2 && ARGS[1] == "t") arg = ARGS[2]
      if (arg == "true" || arg == "True" || arg == "1") emit("TAUT", ln, "tautology: " nm "(" arg ") - cannot fail")
    } else if (nm ~ /^(assert[.](equal|strictEqual|deepEqual|deepStrictEqual|Equal|Exactly)|require[.](Equal|Exactly)|assertEqual|assertEquals|assertIs)$/) {
      n = splitargs(inner)
      if (n >= 3 && ARGS[1] == "t") { ARGS[1] = ARGS[2]; ARGS[2] = ARGS[3]; n = 2 }
      if (n == 2 && issimple(ARGS[1]) && ARGS[1] == ARGS[2]) emit("TAUT", ln, "tautology: " nm "(" ARGS[1] ", " ARGS[2] ") - same value both sides")
    }
  }
  if (LG == "py" && s ~ /^[[:space:]]*assert[[:space:]]/) {
    r = trim(s); r = trim(substr(r, 7))
    if (index(r, ",") == 0) {
      if (r == "True" || r == "1") emit("TAUT", ln, "tautology: assert " r " - cannot fail")
      else {
        p = index(r, " == ")
        if (p > 0 && index(substr(r, p + 4), " == ") == 0) {
          a = trim(substr(r, 1, p - 1)); b = trim(substr(r, p + 4))
          if (issimple(a) && a == b) emit("TAUT", ln, "tautology: assert " a " == " b " - same value both sides")
        }
      }
    }
  }
}
function jsextent(i, col,   d, j, k, line, len, ch) {
  d = 0; BODY = ""
  for (j = i; j <= n && j <= i + 400; j++) {
    line = c[j]; len = length(line); k = (j == i) ? col : 1
    BODY = BODY " " substr(line, k)
    for (; k <= len; k++) {
      ch = substr(line, k, 1)
      if (ch == "(") d++
      else if (ch == ")") { d--; if (d == 0) return j }
    }
  }
  return 0
}
function goextent(i,   d, j, k, line, len, ch, seen) {
  d = 0; seen = 0; BODY = ""
  for (j = i; j <= n && j <= i + 800; j++) {
    line = c[j]; len = length(line)
    BODY = BODY " " line
    for (k = 1; k <= len; k++) {
      ch = substr(line, k, 1)
      if (ch == "{") { d++; seen = 1 }
      else if (ch == "}") { d--; if (seen && d == 0) return j }
    }
  }
  return 0
}
BEGIN {
  SQ = "'"
  JSA = "(^|[^[:alnum:]_])(expect|assert|should|verify|check|ensure|validate|must|fail|done|snapshot|getBy|findBy|getAllBy|findAllBy|throw|resolves|rejects|toBe|toEqual|toMatch|toThrow|toHave|toContain|(cy|page|browser|driver)[.]|screen[.]get|t[.](is|not|true|false|truthy|falsy|deepEqual|throws|notThrows|pass|fail|assert|ok|equal|same|match|snapshot))"
  PYA = "(^|[^[:alnum:]_])(assert|raises|fail|expect|should|verify|check|ensure|validate|warns|approx|snapshot|skip|xfail|raise)"
  GOA = "(^|[^[:alnum:]_])(t[.](Error|Errorf|Fatal|Fatalf|Fail|FailNow|Run|Skip|Skipf|SkipNow)|assert|require|expect|should|verify|check|ensure|validate|must|Fatal|panic|Equal|cmp[.]Diff|reflect[.]DeepEqual)"
}
{ raw[NR] = $0 }
END {
  n = NR
  if (n > 6000 || n == 0) exit 0
  for (i = 1; i <= n; i++) cln(i)
  for (i = 1; i <= n; i++) collect(i)
  mocks = 0
  for (i = 1; i <= n; i++) {
    if (LG == "js" && c[i] ~ /((jest|vi)[.](mock|fn|spyOn)|sinon[.](stub|spy|mock))/) mocks = 1
    if (LG == "py" && c[i] ~ /(mock[.]patch|[@]patch|MagicMock|Mock[(]|mocker[.]patch|monkeypatch)/) mocks = 1
  }
  ntests = 0
  for (i = 1; i <= n; i++) {
    s = c[i]
    if (s ~ /^[[:space:]]*$/) continue
    # ---- focus / skip (line level)
    if (LG == "js") {
      if (s ~ /(^|[^[:alnum:]_])(it|test|describe|context|suite)[.]only[[:space:]]*[(.]/ || s ~ /(^|[^[:alnum:]_.])(fdescribe|fit|fcontext)[[:space:]]*[(]/)
        emit("ONLY", i, "focused test committed (" short(raw[i]) ") - every other test in the run is silently skipped")
      if (s ~ /(^|[^[:alnum:]_])(it|test|describe|context)[.]skip[[:space:]]*[(.]/ || s ~ /(^|[^[:alnum:]_.])(xit|xtest|xdescribe)[[:space:]]*[(]/)
        if (!commentReason(i)) emit("SKIP", i, "skipped test with no reason (add a comment or ticket): " short(raw[i]))
    } else if (LG == "py") {
      if (s ~ /(pytest[.]mark[.]skip|unittest[.]skip|[@]skip)[[:space:]]*($|[(][[:space:]]*[)])/ || s ~ /pytest[.]skip[[:space:]]*[(][[:space:]]*[)]/) {
        if (!commentReason(i)) emit("SKIP", i, "skipped test with no reason string: " short(raw[i]))
      } else if (s ~ /skipif[[:space:]]*[(]/ && s !~ /reason/ && s ~ /[)][[:space:]]*$/) {
        if (!commentReason(i)) emit("SKIP", i, "skipif without reason=: " short(raw[i]))
      }
    } else {
      if (s ~ /t[.](Skip|SkipNow)[[:space:]]*[(][[:space:]]*[)]/ && !commentReason(i)) emit("SKIP", i, "t.Skip() with no reason: " short(raw[i]))
    }
    # ---- tautologies
    taut(cs[i], i)
    # ---- test bodies
    if (LG == "js") {
      if (match(s, /(^|[^[:alnum:]_.$])(it|test|xit|xtest|fit)([.](only|skip|concurrent|each|todo|fails|failing))*[[:space:]]*[(]/)) {
        mt = substr(s, RSTART, RLENGTH); col = RSTART + RLENGTH - 1
        iseach = (index(mt, ".each") > 0)
        ntests++
        if (iseach) continue
        e = jsextent(i, col)
        if (e == 0) continue
        if (BODY !~ /(=>|function)/) continue
        if (c[e] !~ /[)][[:space:]]*;?[[:space:]]*$/) continue
        if (BODY ~ JSA || delegates(BODY)) {
          nexp = cnt(BODY, "(^|[^[:alnum:]_])expect[[:space:]]*[(]")
          nm = cnt(BODY, "[.](toHaveBeenCalled|toBeCalled|toHaveBeenLastCalledWith|toHaveBeenNthCalledWith|toHaveBeenCalledWith|toHaveBeenCalledTimes|toBeCalledWith|toHaveBeenCalledOnce)")
          if (mocks && nm > 0 && nm == nexp) emit("MOCK", i, "HEURISTIC: only asserts that mocks were called and the file mocks its collaborators - proves wiring, not behaviour")
        } else if (BODY ~ /(=>|function[^{]*)[[:space:]]*\{[[:space:]]*\}/) {
          emit("EMPTY", i, "empty test body - passes without checking anything: " short(raw[i]))
        } else {
          emit("NOASSERT", i, "test has no assertion (no expect/assert/should) - it passes as long as nothing throws: " short(raw[i]))
        }
      }
    } else if (LG == "py") {
      if (match(s, /^[[:space:]]*(async[[:space:]]+)?def[[:space:]]+test[[:alnum:]_]*[[:space:]]*[(]/)) {
        d = ind[i]; ntests++
        if (match(s, /[)][[:space:]]*(->[^:]*)?:[[:space:]]*[^[:space:]]/)) {
          st = substr(s, RSTART + RLENGTH - 1)
          if (st ~ /^(pass|[.][.][.])/) emit("EMPTY", i, "empty test body (pass) - passes without checking anything: " short(raw[i]))
          continue
        }
        k = i
        while (k <= n && k < i + 40 && c[k] !~ /:[[:space:]]*$/) k++
        if (k > n || c[k] !~ /:[[:space:]]*$/) continue
        j = k + 1; BODY = ""; nstmt = 0; onlypass = 1; na = 0; nma = 0
        while (j <= n && (c[j] ~ /^[[:space:]]*$/ || ind[j] > d)) {
          if (c[j] !~ /^[[:space:]]*$/) {
            nstmt++
            if (c[j] !~ /^[[:space:]]*(pass|[.][.][.]|"")[[:space:]]*$/) onlypass = 0
            if (c[j] ~ /(^|[^[:alnum:]_])assert/) { na++; if (c[j] ~ /(assert_called|assert_any_call|assert_has_calls|assert_not_called|[.]called|call_count|call_args)/) nma++ }
          }
          BODY = BODY " " c[j]; j++
        }
        if (nstmt == 0 || onlypass) emit("EMPTY", i, "empty test body - passes without checking anything: " short(raw[i]))
        else if (BODY ~ PYA || delegates(BODY)) {
          if (mocks && na > 0 && na == nma) emit("MOCK", i, "HEURISTIC: only asserts that mocks were called and the file mocks its collaborators - proves wiring, not behaviour")
        } else emit("NOASSERT", i, "test has no assertion (no assert/raises/self.assert*) - it passes as long as nothing throws: " short(raw[i]))
      }
    } else {
      if (match(s, /^func[[:space:]]+Test[[:upper:][:digit:]_][[:alnum:]_]*[[:space:]]*[(]/) && s !~ /^func[[:space:]]+TestMain/) {
        ntests++
        e = goextent(i)
        if (e == 0) continue
        t = BODY; sub(/^[^{]*[{]/, "", t); sub(/[}][[:space:]]*$/, "", t)
        if (t ~ /^[[:space:]]*$/) emit("EMPTY", i, "empty test function - passes without checking anything: " short(raw[i]))
        else if (BODY ~ GOA || BODY ~ /[(,][[:space:]]*t[,)]/ || delegates(BODY)) { }
        else emit("NOASSERT", i, "test has no assertion (no t.Error/t.Fatal/assert/require) - it passes as long as nothing panics: " short(raw[i]))
      }
    }
  }
  print "TESTS|" F "|0|" ntests
}
AWK
}

tq_init() {
  [ -n "${TQ_AWK:-}" ] && [ -f "$TQ_AWK" ] && return 0
  TQ_AWK=$(mktemp "${TMPDIR:-/tmp}/mogger-tq.XXXXXX") || return 1
  tq_awk_prog > "$TQ_AWK" || return 1
}

tq_is_test_path() {
  local p="$1" b ext
  case "$p" in *node_modules/*|*/.git/*|*/dist/*|*/build/*|*/venv/*|*/.venv/*) return 1 ;; esac
  b="${p##*/}"
  case "$b" in
    test_*.py|*_test.py|*_test.go|*.test.js|*.test.ts|*.test.jsx|*.test.tsx|*.test.mjs|*.test.cjs|*.spec.*) return 0 ;;
  esac
  ext="${b##*.}"
  case "$ext" in py|js|ts|jsx|tsx|mjs|cjs|go) ;; *) return 1 ;; esac
  case "$p" in
    tests/*|test/*|__tests__/*|*/tests/*|*/test/*|*/__tests__/*) return 0 ;;
  esac
  return 1
}

# tq_scan_file <path>  -> KIND|file|line|msg on stdout (never fails)
tq_scan_file() {
  local f="$1" b ext lg
  [ -f "$f" ] && [ -r "$f" ] || return 0
  b="${f##*/}"; ext="${b##*.}"
  case "$ext" in
    py) lg=py ;;
    go) lg=go ;;
    js|jsx|ts|tsx|mjs|cjs|mts|cts) lg=js ;;
    *) return 0 ;;
  esac
  case "$(wc -c < "$f" 2>/dev/null | tr -d ' ')" in
    ''|*[!0-9]*) return 0 ;;
    *) [ "$(wc -c < "$f" | tr -d ' ')" -gt 1000000 ] && return 0 ;;
  esac
  tq_init || return 0
  awk -v LG="$lg" -v F="$f" -f "$TQ_AWK" "$f" 2>/dev/null || true
  return 0
}

tq_json_escape() {
  printf '%s' "$1" | tr '\t' ' ' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | awk 'BEGIN{ORS="\\n"}{print}'
}

[ "${MOGGER_TQ_SOURCE_ONLY:-}" = "1" ] && return 0 2>/dev/null

if [ "${1:-}" = "--scan" ]; then
  shift
  trap 'rm -f "${TQ_AWK:-}"' EXIT
  for f in "$@"; do tq_scan_file "$f"; done
  exit 0
fi

source "$(dirname "$0")/lib.sh"
[ "${MOGGER_CHECK_TESTS:-on}" = "off" ] && exit 0

INPUT=$(cat)
FP=$(json_get "$INPUT" '.tool_input.file_path')
[ -n "$FP" ] || exit 0
REL="$FP"
case "$FP" in "$PWD"/*) REL="${FP#"$PWD"/}" ;; esac
tq_is_test_path "$REL" || exit 0
[ -f "$FP" ] || exit 0

trap 'rm -f "${TQ_AWK:-}"' EXIT
OUT=$(tq_scan_file "$FP") || exit 0
[ -n "$OUT" ] || exit 0

BLOCK=""; WARN=""
while IFS='|' read -r kind file line msg; do
  case "$kind" in
    EMPTY|NOASSERT|TAUT|ONLY) BLOCK="${BLOCK}  ${REL}:${line}: ${msg}
" ;;
    SKIP|MOCK) WARN="${WARN}  ${REL}:${line}: ${msg}
" ;;
  esac
done <<EOT
$OUT
EOT

if [ -n "$BLOCK" ]; then
  {
    mogger_event block "blocked fake tests in ${REL##*/}"; echo "BLOCKED: fake tests - these cannot fail, so they prove nothing:"
    printf '%s' "$BLOCK"
    if [ -n "$WARN" ]; then echo "Also (warnings):"; printf '%s' "$WARN"; fi
    echo "Fix: make each test assert an observable result (a return value, a state change, a thrown error) that would differ if the code were wrong. Remove .only. Set MOGGER_CHECK_TESTS=off to disable this check."
  } >&2
  exit 2
fi

if [ -n "$WARN" ]; then
  mogger_event warn "weak tests in ${REL##*/}"
  printf 'WARN (test quality):\n%s' "$WARN" >&2
  if command -v jq >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1; then
    printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' "$(tq_json_escape "Test quality warnings (not blocking):
$WARN")"
  fi
fi
exit 0
