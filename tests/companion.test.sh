#!/usr/bin/env bash
# Tests for cost-cap.sh, update-status.sh, cost-report.sh. Run: bash tests/companion.test.sh
# Synthetic transcripts with known token counts; expected dollars are worked
# out by hand against a FIXTURE pricing file (haiku 1/5, sonnet 2/10, opus
# 4/20 per Mtok), so a later edit to templates/pricing.json can't break them.
# Exits non-zero on any failure.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
H="$ROOT/hooks/scripts"
PASS=0; FAIL=0

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
cd "$SANDBOX"
git init -q -b main . 2>/dev/null || { git init -q .; git checkout -q -b main; }
git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init

cat > "$SANDBOX/pricing.json" <<'J'
{"models":{"haiku":{"input_per_mtok":1.00,"output_per_mtok":5.00},
"sonnet":{"input_per_mtok":2.00,"output_per_mtok":10.00},
"opus":{"input_per_mtok":4.00,"output_per_mtok":20.00}}}
J
export MOGGER_PRICING_FILE="$SANDBOX/pricing.json"
unset MOGGER_BUDGET_USD MOGGER_BUDGET_OVERRIDE

ok()   { PASS=$((PASS+1)); printf '  ok   %-16s %s\n' "$1" "$2"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %-16s %s\n' "$1" "$2"; }
check() {  # check <label> <desc> <command...>  (passes if command succeeds)
  local l="$1" d="$2"; shift 2
  if "$@" >/dev/null 2>&1; then ok "$l" "$d"; else bad "$l" "$d"; fi
}

T="$SANDBOX/t.jsonl"
# tl <model> <in> <out> <cache_read> <cache_write> [id]
tl() {
  local id="${6:-}"; local idj=""
  [ -n "$id" ] && idj="\"id\":\"$id\","
  printf '{"type":"assistant","message":{%s"model":"%s","usage":{"input_tokens":%s,"output_tokens":%s,"cache_read_input_tokens":%s,"cache_creation_input_tokens":%s}}}\n' \
    "$idj" "$1" "$2" "$3" "$4" "$5" >> "$T"
}
fresh() { : > "$T"; rm -f .claude/state/cost.json; }
hook_json() { printf '{"tool_name":"Bash","transcript_path":"%s","tool_input":{}}' "${1:-$T}"; }

# cap <budget> <want_exit> <desc>  — runs cost-cap on current $T with a clean state
ERR=""
cap() {
  local budget="$1" want="$2" desc="$3" got
  rm -f .claude/state/cost.json
  ERR=$(hook_json | MOGGER_BUDGET_USD="$budget" bash "$H/cost-cap.sh" 2>&1 >/dev/null); got=$?
  if [ "$got" -eq "$want" ]; then ok cost-cap.sh "$desc"; else bad cost-cap.sh "$desc (want $want, got $got)"; fi
}
cj() { grep -q "$1" .claude/state/cost.json 2>/dev/null; }

echo "== cost-cap.sh: off / fail-open"
fresh; tl claude-sonnet-5-5 1000000 0 0 0
got=0; hook_json | bash "$H/cost-cap.sh" >/dev/null 2>&1 || got=$?
[ "$got" -eq 0 ] && ok cost-cap.sh "budget unset => allow" || bad cost-cap.sh "budget unset => allow"
check cost-cap.sh "budget unset => no cost.json written" test ! -f .claude/state/cost.json
cap 0 0 "budget 0 => feature off, allow"
cap abc 0 "non-numeric budget => allow"
rm -f .claude/state/cost.json
got=0; printf '{"transcript_path":"%s/nope.jsonl"}' "$SANDBOX" | MOGGER_BUDGET_USD=1 bash "$H/cost-cap.sh" >/dev/null 2>&1 || got=$?
[ "$got" -eq 0 ] && ok cost-cap.sh "missing transcript => allow" || bad cost-cap.sh "missing transcript => allow"
got=0; printf '{"tool_name":"Bash"}' | MOGGER_BUDGET_USD=1 bash "$H/cost-cap.sh" >/dev/null 2>&1 || got=$?
[ "$got" -eq 0 ] && ok cost-cap.sh "no transcript_path => allow" || bad cost-cap.sh "no transcript_path => allow"
got=0; printf 'not json at all' | MOGGER_BUDGET_USD=1 bash "$H/cost-cap.sh" >/dev/null 2>&1 || got=$?
[ "$got" -eq 0 ] && ok cost-cap.sh "garbage hook input => allow" || bad cost-cap.sh "garbage hook input => allow"
got=0; hook_json | MOGGER_PRICING_FILE="$SANDBOX/absent.json" MOGGER_BUDGET_USD=1 bash "$H/cost-cap.sh" >/dev/null 2>&1 || got=$?
[ "$got" -eq 0 ] && ok cost-cap.sh "missing pricing file => allow" || bad cost-cap.sh "missing pricing file => allow"

echo "== cost-cap.sh: boundaries (1M sonnet input = exactly \$2.00)"
fresh; tl claude-sonnet-5-5 1000000 0 0 0
cap 10 0 "20% of budget => allow"
check cost-cap.sh "cost.json spent_usd 2.0" cj '"spent_usd": 2.0'
check cost-cap.sh "cost.json pct 20.0" cj '"pct": 20.0'
check cost-cap.sh "cost.json estimated true" cj '"estimated": true'
check cost-cap.sh "cost.json has model breakdown" cj 'claude-sonnet-5-5'
check cost-cap.sh "no warning below 80%" test -z "$ERR"
cap 2.5001 0 "79.99% => allow, no warning"
check cost-cap.sh "no stderr warning at 79.99%" test -z "$ERR"
cap 2.5 0 "exactly 80% => allow"
case "$ERR" in *"80%"*) ok cost-cap.sh "exactly 80% => stderr warning" ;; *) bad cost-cap.sh "exactly 80% => stderr warning" ;; esac
check cost-cap.sh "80% warning recorded in cost.json" cj '"warning": "Over 80%'
cap 2.0001 0 "99.995% => allow (warn)"
cap 2 2 "exactly 100% => block"
case "$ERR" in *'Budget $2 reached ($2.00 spent, estimated from transcript). Stop and tell the user; they can raise MOGGER_BUDGET_USD.'*) ok cost-cap.sh "block message exact" ;; *) bad cost-cap.sh "block message exact: $ERR" ;; esac
cap 1 2 "200% => block"
rm -f .claude/state/cost.json
got=0; hook_json | MOGGER_BUDGET_USD=1 MOGGER_BUDGET_OVERRIDE=on bash "$H/cost-cap.sh" >/dev/null 2>&1 || got=$?
[ "$got" -eq 0 ] && ok cost-cap.sh "MOGGER_BUDGET_OVERRIDE=on => allow over budget" || bad cost-cap.sh "override => allow"
check cost-cap.sh "override still writes cost.json" cj '"pct": 200.0'

echo "== cost-cap.sh: pricing rules"
fresh; tl claude-sonnet-5-5 0 100000 0 0          # 0.1M out x \$10 = \$1.00
cap 1 2 "output tokens priced at output rate (\$1.00)"
fresh; tl claude-sonnet-5-5 0 0 1000000 0         # cache read = 10% of \$2 = \$0.20
cap 0.2 2 "cache read = 10% of input rate (\$0.20)"
cap 0.25 0 "cache read: exactly 80% of \$0.25 => allow"
fresh; tl claude-sonnet-5-5 0 0 0 1000000         # cache write = 125% of \$2 = \$2.50
cap 2.5 2 "cache write = 125% of input rate (\$2.50)"
cap 2.51 0 "cache write: just under budget => allow"
fresh; tl claude-haiku-4-5 1000000 1000000 0 0    # 1 + 5 = \$6
tl claude-opus-5-5 1000000 0 0 0                  # 4
cap 10 2 "mixed haiku+opus = exactly \$10 => block"
cap 10.01 0 "mixed haiku+opus under \$10.01 => allow"
check cost-cap.sh "per-model haiku \$6.0" cj '"claude-haiku-4-5": 6.0'
check cost-cap.sh "per-model opus \$4.0" cj '"claude-opus-5-5": 4.0'
fresh; tl some-new-model-9 1000000 0 0 0          # unknown => sonnet rate \$2
cap 2 2 "unknown model priced at sonnet rate"
check cost-cap.sh "unknown model flagged" cj 'models_unknown": \["some-new-model-9"\]'
fresh; tl claude-sonnet-5-5 1000000 0 0 0 msg_1; tl claude-sonnet-5-5 1000000 0 0 0 msg_1
cap 4 0 "duplicate message.id counted once (\$2 of \$4 => allow)"
check cost-cap.sh "dedupe: spent 2.0" cj '"spent_usd": 2.0'
fresh; printf 'garbage line\n\n{"type":"user","message":{"content":"hi"}}\n' >> "$T"; tl claude-sonnet-5-5 1000000 0 0 0
cap 2 2 "junk / user lines ignored, valid usage still counted"

echo "== cost-cap.sh: throttle + warn-once"
fresh; tl claude-sonnet-5-5 1000000 0 0 0
run_cap() { hook_json | MOGGER_BUDGET_USD="$1" bash "$H/cost-cap.sh" 2>&1 >/dev/null; return $?; }
ERR=$(run_cap 2.5); rc=$?
[ "$rc" -eq 0 ] && case "$ERR" in *80%*) ok cost-cap.sh "first run at 80% warns" ;; *) bad cost-cap.sh "first run should warn" ;; esac
tl claude-sonnet-5-5 5000000 0 0 0                # transcript now \$12 total
ERR=$(run_cap 2.5); rc=$?
[ "$rc" -eq 0 ] && ok cost-cap.sh "within 20s: cached value, no recompute (allow)" || bad cost-cap.sh "throttle should reuse cache (rc=$rc)"
touch -t 200001010000 .claude/state/cost.json
ERR=$(run_cap 2.5); rc=$?
[ "$rc" -eq 2 ] && ok cost-cap.sh "after 20s: recomputed, now over budget => block" || bad cost-cap.sh "aged cache should recompute (rc=$rc)"
# warn-once
fresh; tl claude-sonnet-5-5 1000000 0 0 0
run_cap 2.5 >/dev/null; touch -t 200001010000 .claude/state/cost.json
ERR=$(run_cap 2.5); rc=$?
[ "$rc" -eq 0 ] && [ -z "$ERR" ] && ok cost-cap.sh "80% warning printed only once" || bad cost-cap.sh "warning repeated (rc=$rc, err=$ERR)"
# budget change bypasses throttle
ERR=$(run_cap 1); rc=$?
[ "$rc" -eq 2 ] && ok cost-cap.sh "changed budget bypasses throttle" || bad cost-cap.sh "budget change should recompute (rc=$rc)"

echo "== cost-report.sh"
fresh; tl claude-sonnet-5-5 1000000 0 0 0; cap 10 0 "seed cost.json" >/dev/null 2>&1
OUT=$(bash "$ROOT/scripts/cost-report.sh" 2>&1)
case "$OUT" in *'about $2.00 of a $10.00 budget (20.0%)'*) ok cost-report.sh "plain-words summary" ;; *) bad cost-report.sh "summary: $OUT" ;; esac
case "$OUT" in *estimate*) ok cost-report.sh "says estimate" ;; *) bad cost-report.sh "missing estimate wording" ;; esac
rm -f .claude/state/cost.json
OUT=$(bash "$ROOT/scripts/cost-report.sh" 2>&1)
case "$OUT" in *"No cost data yet"*) ok cost-report.sh "no data message" ;; *) bad cost-report.sh "no-data: $OUT" ;; esac

echo "== update-status.sh"
mt() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }
su() { printf '{}' | bash "$H/update-status.sh" >/dev/null 2>&1; echo $?; }
rm -rf .claude STATUS.md TASKS.md
[ "$(su)" = "0" ] && ok update-status.sh "no TASKS.md => exit 0" || bad update-status.sh "no TASKS.md exit"
check update-status.sh "no TASKS.md => no STATUS.md created" test ! -f STATUS.md
printf '# T\n\n- [x] 1. one\n- [x] 2. two\n- [ ] 3. three\n- [ ] 4. four\n- [ ] 5. five\n- [ ] 6. six\n' > TASKS.md
for f in a.txt b.txt c.txt d.txt e.txt f.txt g.txt; do echo x > "$f"; done
touch -t 202601010001 a.txt; touch -t 202601010002 b.txt; touch -t 202601010003 c.txt; touch -t 202601010004 d.txt
touch -t 202601010005 e.txt; touch -t 202601010006 f.txt; touch -t 202601010007 g.txt
[ "$(su)" = "0" ] && ok update-status.sh "with TASKS.md => exit 0" || bad update-status.sh "exit code"
check update-status.sh "STATUS.md created" test -f STATUS.md
check update-status.sh "counts: 2 done, 4 open" grep -q '2 done, 4 open' STATUS.md
check update-status.sh "next 3 listed" sh -c 'grep -q "^- 3. three" STATUS.md && grep -q "^- 5. five" STATUS.md'
check update-status.sh "4th open task not in next-3" sh -c '! grep -q "^- 6. six" STATUS.md'
check update-status.sh "last 5 files: newest g.txt listed" grep -q '^- g.txt' STATUS.md
check update-status.sh "last 5 files: 6th oldest (b.txt) omitted" sh -c '! grep -q "^- b.txt" STATUS.md'
check update-status.sh "no temp files left behind" sh -c 'ls STATUS.md.tmp.* 2>/dev/null | wc -l | grep -q "^ *0$"'
check update-status.sh "has Updated timestamp" grep -q '^_Updated: ' STATUS.md
check update-status.sh "no BLOCKED section when none" sh -c '! grep -q "^## Blocked" STATUS.md'
check update-status.sh "cost untracked message" grep -q 'not tracked' STATUS.md
touch -t 200001010000 STATUS.md; OLD=$(mt STATUS.md)
[ "$(su)" = "0" ] && ok update-status.sh "rerun unchanged => exit 0" || bad update-status.sh "rerun exit"
[ "$(mt STATUS.md)" = "$OLD" ] && ok update-status.sh "unchanged content => mtime not bumped" || bad update-status.sh "mtime was bumped"
printf 'BLOCKED: waiting on API key\n' >> TASKS.md
su >/dev/null
check update-status.sh "changed content => rewritten" test "$(mt STATUS.md)" != "$OLD"
check update-status.sh "BLOCKED line shown" grep -q 'BLOCKED: waiting on API key' STATUS.md
printf '## Status: awaiting-approval\n' >> TASKS.md; su >/dev/null
check update-status.sh "Status line shown" grep -q 'Status: awaiting-approval' STATUS.md
mkdir -p .claude/state
echo '{"status":"pass"}' > .claude/state/last_test_result.json
su >/dev/null
check update-status.sh "test marker time shown" grep -q 'last checkpoint/test marker: 20' STATUS.md
fresh; tl claude-sonnet-5-5 1000000 0 0 0; cap 2.5 0 "seed" >/dev/null 2>&1
su >/dev/null
check update-status.sh "cost shown from cost.json" grep -q 'about \$2.0 spent of \$2.5 budget (80.0%)' STATUS.md
check update-status.sh "cost warning surfaced" grep -q 'WARNING: Over 80%' STATUS.md
rm -f .claude/state/cost.json; su >/dev/null
check update-status.sh "cost section reverts when cost.json gone" grep -q 'not tracked' STATUS.md
check update-status.sh "TASKS.md untouched by hook" grep -q '^- \[ \] 3. three' TASKS.md
got=0; printf '' | (cd / && bash "$H/update-status.sh") >/dev/null 2>&1 || got=$?
[ "$got" -eq 0 ] && ok update-status.sh "outside any project => exit 0" || bad update-status.sh "outside project"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
