#!/usr/bin/env bash
# Tests for spec-first + decisions memory. Run: bash tests/planning.test.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
H="$ROOT/hooks/scripts"
PASS=0; FAIL=0

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
cd "$SANDBOX"

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

# json string escaper, pure bash (backslash, quote, newline, tab)
esc() {
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"; s="${s//$'\t'/\\t}"
  printf '"%s"' "$s"
}
edit_json()  { printf '{"tool_name":"Edit","tool_input":{"file_path":%s,"old_string":%s,"new_string":%s}}' "$(esc "$1")" "$(esc "$2")" "$(esc "$3")"; }
write_json() { printf '{"tool_name":"Write","tool_input":{"file_path":%s,"content":%s}}' "$(esc "$1")" "$(esc "$2")"; }

expect() {  # expect <exit> <json> <desc> [env-assignment]
  local want="$1" json="$2" desc="$3" got
  printf '%s' "$json" | bash "$H/protect-decisions.sh" >/dev/null 2>&1; got=$?
  if [ "$got" -eq "$want" ]; then ok "protect-decisions: $desc"
  else bad "protect-decisions: $desc (want $want, got $got)"; fi
}
expect_out() {  # expect_out <expected-string> <actual> <desc>
  if [ "$1" = "$2" ]; then ok "$3"; else bad "$3"; printf '       want: [%s]\n       got:  [%s]\n' "$1" "$2"; fi
}

echo "== decisions-context.sh"
D="$SANDBOX/DECISIONS.md"
out=$(bash "$H/decisions-context.sh" "$SANDBOX/nope.md"); rc=$?
expect_out "" "$out" "missing file prints nothing"
[ "$rc" -eq 0 ] && ok "missing file exits 0" || bad "missing file exits 0"

: > "$D"
out=$(bash "$H/decisions-context.sh" "$D")
expect_out "" "$out" "empty file prints nothing"

cp "$ROOT/templates/DECISIONS.md" "$D"
out=$(bash "$H/decisions-context.sh" "$D")
expect_out "" "$out" "template alone (example in comment) prints nothing"

mk() { # mk <n> <title> <why> <status>
  printf '\n## #%s — %s\n- Date: 2026-01-01\n- Decision: x\n- Why: %s\n- Alternatives rejected: y\n- Evidence: z\n- Status: %s\n' "$1" "$2" "$3" "$4"
}
{ mk 1 "Use SQLite" "one user, no server" active
  mk 2 "Use Postgres" "scale" "superseded-by #3"
  mk 3 "Use SQLite again" "simple" active; } >> "$D"
out=$(bash "$H/decisions-context.sh" "$D")
expect_out "#1 Use SQLite — one user, no server
#3 Use SQLite again — simple" "$out" "active shown, superseded skipped"
case "$out" in *"#2"*) bad "superseded #2 absent";; *) ok "superseded #2 absent";; esac

: > "$D"
i=1; while [ $i -le 25 ]; do mk $i "Title $i" "why $i" active >> "$D"; i=$((i+1)); done
out=$(bash "$H/decisions-context.sh" "$D")
expect_out "20" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "cap: 25 entries print 20 lines"
expect_out "#6 Title 6 — why 6" "$(printf '%s\n' "$out" | head -n 1)" "cap keeps most recent (first is #6)"
expect_out "#25 Title 25 — why 25" "$(printf '%s\n' "$out" | tail -n 1)" "cap keeps most recent (last is #25)"

printf '## #1 — No status line\n- Why: default active\n' > "$D"
out=$(bash "$H/decisions-context.sh" "$D")
expect_out "#1 No status line — default active" "$out" "missing Status line counts as active"

printf '## #1 — Cased\n- Why: ok\n- Status: Superseded-by #2\n' > "$D"
out=$(bash "$H/decisions-context.sh" "$D")
expect_out "" "$out" "superseded match is case-insensitive"

# sourced use
printf '## #4 — Sourced\n- Why: works\n- Status: active\n' > "$D"
out=$(source "$H/decisions-context.sh"; decisions_context "$D")
expect_out "#4 Sourced — works" "$out" "sourced: decisions_context function works"
out=$(cd "$SANDBOX" && CLAUDE_PROJECT_DIR="$SANDBOX" bash "$H/decisions-context.sh")
expect_out "#4 Sourced — works" "$out" "default path via CLAUDE_PROJECT_DIR"

echo "== protect-decisions.sh"
D="$SANDBOX/DECISIONS.md"
BASE="# DECISIONS

## #1 — Use SQLite
- Why: simple
- Status: active
"
printf '%s' "$BASE" > "$D"

expect 0 "$(edit_json "$D" "- Status: active
" "- Status: active

## #2 — New
- Why: more
- Status: active
")" "append via Edit (new starts with old)"
expect 2 "$(edit_json "$D" "- Why: simple" "- Why: complicated")" "edit of existing line blocked"
expect 2 "$(edit_json "$D" "## #1 — Use SQLite
" "")" "delete via Edit blocked"
expect 2 "$(edit_json "$D" "Use SQLite" "Use Postgres")" "rename in place blocked"
expect 0 "$(edit_json "$D" "- Status: active" "- Status: superseded-by #2")" "flip Status active to superseded-by allowed"
expect 2 "$(edit_json "$D" "- Status: active" "- Status: superseded-by #2 and more")" "flip with extra text blocked"
expect 2 "$(edit_json "$D" "- Why: simple
- Status: active" "- Why: rewritten
- Status: superseded-by #2")" "flip bundled with other change blocked"
expect 0 "$(edit_json "$D" "" "anything")" "Edit with empty old_string allowed"
expect 0 "$(write_json "$D" "${BASE}
## #2 — Appended
- Why: yes
- Status: active
")" "Write that keeps all existing content allowed"
expect 2 "$(write_json "$D" "# DECISIONS
")" "Write that truncates blocked"
expect 2 "$(write_json "$D" "totally new content")" "Write-over blocked"
expect 2 "$(write_json "$D" "")" "Write empty over existing blocked"
expect 0 "$(write_json "$SANDBOX/sub/DECISIONS.md" "fresh")" "Write to nonexistent DECISIONS.md allowed (fresh create)"
expect 0 "$(edit_json "$SANDBOX/sub/DECISIONS.md" "a" "b")" "Edit on nonexistent file allowed (tool will error itself)"

printf 'hello\n' > "$SANDBOX/OTHER.md"
expect 0 "$(edit_json "$SANDBOX/OTHER.md" "hello" "bye")" "other file Edit untouched"
expect 0 "$(write_json "$SANDBOX/OTHER.md" "overwrite")" "other file Write untouched"
expect 0 "$(edit_json "$SANDBOX/NOTDECISIONS.md" "a" "b")" "similar name untouched"
expect 0 '{"tool_name":"Write","tool_input":{}}' "no file_path fails open"
expect 0 'not json' "garbage input fails open"

# lock off
printf '%s' "$BASE" > "$D"
printf '%s' "$(edit_json "$D" "- Why: simple" "- Why: changed")" | MOGGER_DECISIONS_LOCK=off bash "$H/protect-decisions.sh" >/dev/null 2>&1; got=$?
[ "$got" -eq 0 ] && ok "protect-decisions: MOGGER_DECISIONS_LOCK=off allows edit" || bad "protect-decisions: lock off (got $got)"
printf '%s' "$(write_json "$D" "wiped")" | MOGGER_DECISIONS_LOCK=off bash "$H/protect-decisions.sh" >/dev/null 2>&1; got=$?
[ "$got" -eq 0 ] && ok "protect-decisions: lock off allows Write-over" || bad "protect-decisions: lock off Write (got $got)"
printf '%s' "$(edit_json "$D" "- Why: simple" "- Why: changed")" | MOGGER_DECISIONS_LOCK=on bash "$H/protect-decisions.sh" >/dev/null 2>&1; got=$?
[ "$got" -eq 2 ] && ok "protect-decisions: lock on still blocks" || bad "protect-decisions: lock on (got $got)"
# stderr message
msg=$(printf '%s' "$(edit_json "$D" "- Why: simple" "- Why: changed")" | bash "$H/protect-decisions.sh" 2>&1 >/dev/null)
case "$msg" in *append-only*) ok "protect-decisions: block message explains append-only";; *) bad "block message";; esac
# file untouched by the hook
expect_out "$(printf '%s' "$BASE")" "$(cat "$D")" "hook never modifies DECISIONS.md"

echo "== files and frontmatter"
fm() {  # fm <file> <key>: value of key inside first frontmatter block
  awk -v k="$2" 'NR==1 && $0!="---"{exit} NR>1 && $0=="---"{exit} NR>1 && index($0,k":")==1{sub("^"k":[ ]*","");print;exit}' "$1"
}
for f in skills/mogger-idea/SKILL.md skills/mogger-decisions/SKILL.md agents/planner.md; do
  [ -f "$ROOT/$f" ] && ok "exists: $f" || bad "exists: $f"
  [ -n "$(fm "$ROOT/$f" name)" ] && ok "frontmatter name: $f" || bad "frontmatter name: $f"
  [ -n "$(fm "$ROOT/$f" description)" ] && ok "frontmatter description: $f" || bad "frontmatter description: $f"
done
expect_out "mogger-idea" "$(fm "$ROOT/skills/mogger-idea/SKILL.md" name)" "mogger-idea name matches dir"
expect_out "mogger-decisions" "$(fm "$ROOT/skills/mogger-decisions/SKILL.md" name)" "mogger-decisions name matches dir"
for f in templates/SPEC.md templates/DECISIONS.md hooks/scripts/decisions-context.sh hooks/scripts/protect-decisions.sh; do
  [ -f "$ROOT/$f" ] && ok "exists: $f" || bad "exists: $f"
done
for sec in "## Goal" "## Users" "## Must have" "## Won't do (this round)" "## Data" "## Done when" "## Assumptions" "## Open questions"; do
  grep -qF "$sec" "$ROOT/templates/SPEC.md" && ok "SPEC template has '$sec'" || bad "SPEC template has '$sec'"
done
grep -q 'UNVERIFIED:' "$ROOT/templates/SPEC.md" && ok "SPEC template shows UNVERIFIED: label" || bad "SPEC UNVERIFIED label"
grep -q 'SPEC.md' "$ROOT/agents/planner.md" && grep -q "invent requirements" "$ROOT/agents/planner.md" && ok "planner has SPEC.md section" || bad "planner SPEC section"
grep -q 'DECISIONS.md' "$ROOT/skills/mogger-init/SKILL.md" && ok "mogger-init lists DECISIONS.md" || bad "mogger-init lists DECISIONS.md"
grep -qi "cite" "$ROOT/skills/mogger-decisions/SKILL.md" && ok "decisions skill has cite-then-ask rule" || bad "cite rule"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
