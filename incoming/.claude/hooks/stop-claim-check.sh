#!/usr/bin/env bash
# Stop — no matcher
# False "done" guard. When the turn edited code and the final message claims it is
# done, send the model back ONCE to check each thing the user asked for against real
# output (one command per requirement, one awkward input). Costs one short extra turn
# only when a claim follows code edits; silent for questions, docs-only work, and
# turns that do not claim success. Fires once per stop (stop_hook_active).
# Needs python3 (fails open without it). "Code edited this turn" comes from the transcript when it is
# readable, else from a git or file-time fingerprint kept in .claude/state/claim-check.fp (the eval
# runner and some CLIs do not write a transcript).
# Modes (MOGGER_CLAIM_CHECK): proof (default) blocks only when nothing ran after the last code edit,
# so it costs nothing when the model already ran something. always also sends the requirement check
# after every claim (MEASURED: +62% cost per run on the hard set, no pass-rate gain, so not the default).
# off disables it.
source "$(dirname "$0")/lib.sh"

MODE="${MOGGER_CLAIM_CHECK:-proof}"   # proof (default) | always | off
[ "$MODE" = "off" ] && exit 0
INPUT=$(cat)
[ "$(json_get "$INPUT" '.stop_hook_active')" = "true" ] && exit 0
TP=$(json_get "$INPUT" '.transcript_path')
command -v python3 >/dev/null 2>&1 && python3 -c '1' >/dev/null 2>&1 || exit 0

source "$(dirname "$0")/claim-lib.sh"
FP=$(fingerprint)
OLD=$(cat "$FPF" 2>/dev/null)
mkdir -p .claude/state 2>/dev/null; printf '%s' "$FP" > "$FPF" 2>/dev/null
[ -n "$OLD" ] || OLD="$FP"   # no baseline (session-start writes one): only the transcript can say
CHANGED=0; [ "$FP" != "$OLD" ] && CHANGED=1
HAVE_TP=0; [ -n "$TP" ] && [ -f "$TP" ] && HAVE_TP=1
[ "$HAVE_TP" = 1 ] || [ "$CHANGED" = 1 ] || exit 0

LAM=$(json_get "$INPUT" '.last_assistant_message')
VERDICT=$(LAM="$LAM" HAVE_TP="$HAVE_TP" CHANGED="$CHANGED" python3 - "$TP" <<'PY' 2>/dev/null
import json, os, re, sys
CLAIM = re.compile(r"\b(done|complete[d]?|finished|implemented|fixed|added|works?|working|ready|(is|are) in|(all|whole|suite|tests?|checks?)\b.{0,20}\b(pass(es|ed|ing)?|green))\b", re.I)
DOC = re.compile(r"\.(md|txt|rst|json|ya?ml|toml|lock|csv)$", re.I)
WRITE = re.compile(r"(\bsed -i|\btee |>>?\s*[\w./-]+\.(py|js|jsx|ts|tsx|go|rs|rb|java|c|cc|cpp|h|sh|php)\b|write_text|open\([^)]*,\s*['\"][wa]|\bperl -pi|\bpatch |git apply)", re.I)
TESTRUN = re.compile(r"(unittest|pytest|npm (run )?test|yarn test|go test|cargo test|jest|vitest|make test)", re.I)
RUN = re.compile(r"(test|pytest|unittest|jest|vitest|npm (run|start)|node |python3? |go (run|test|build)|cargo |make|curl |bash |sh |\./)", re.I)
turn = []   # blocks since the last real user message
for line in (open(sys.argv[1], errors="replace") if os.environ.get("HAVE_TP") == "1" else []):
    try: e = json.loads(line)
    except Exception: continue
    m = e.get("message") or {}
    c = m.get("content")
    if e.get("type") == "user" and not (isinstance(c, list) and c and all(isinstance(b, dict) and b.get("type") == "tool_result" for b in c)):
        turn = []
    elif e.get("type") == "assistant" and isinstance(c, list):
        turn += [b for b in c if isinstance(b, dict)]
last_text = ""
for b in reversed(turn):
    if b.get("type") == "text" and b.get("text", "").strip():
        last_text = b["text"]; break
last_text = os.environ.get("LAM") or last_text
edited = False; ran_after_edit = False
for b in turn:
    if b.get("type") != "tool_use": continue
    inp = b.get("input") or {}
    if b.get("name") in ("Edit", "Write", "MultiEdit"):
        p = inp.get("file_path", "")
        if p and not DOC.search(p):
            edited = True; ran_after_edit = False
    elif b.get("name") == "Bash":
        cmd = inp.get("command", "")
        if WRITE.search(cmd):
            edited = True; ran_after_edit = bool(TESTRUN.search(cmd))
        elif edited and RUN.search(cmd):
            ran_after_edit = True
if os.environ.get("HAVE_TP") != "1":
    edited, ran_after_edit = os.environ.get("CHANGED") == "1", True   # no transcript: cannot tell if it ran
if edited and CLAIM.search(last_text):
    print("noproof" if not ran_after_edit else "check")
PY
)
[ -n "$VERDICT" ] || exit 0
[ "$MODE" = "always" ] || [ "$VERDICT" = "noproof" ] || exit 0

mogger_event block "done claim after code edits ($VERDICT)"
if [ "$VERDICT" = "noproof" ]; then
  echo "NOT PROVEN: you said it is done, but nothing ran after your last code edit. Run it." >&2
fi
cat >&2 <<'MSG'
CHECK BEFORE "DONE": re-read the user's request. For each thing they asked for, run one command whose output shows it works (not just the old tests). Try one awkward input (rounding, empty, huge, duplicate). Fix what fails. Then give a short answer: each requirement, and the output that proves it.
MSG
exit 2
