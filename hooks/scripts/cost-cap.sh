#!/usr/bin/env bash
# PreToolUse — matcher: Bash|Edit|Write|Task
# Session cost cap. Reads the REAL session transcript (transcript_path in the
# hook JSON; JSONL whose assistant entries carry message.usage and
# message.model), sums token usage, prices it with templates/pricing.json.
#
# THE NUMBER IS AN ESTIMATE: token counts x published per-token rates, not a
# bill. Rates change and sources disagree; see the _disclaimer in
# templates/pricing.json and verify at https://claude.com/pricing.
# Pricing rules: model id containing haiku/sonnet/opus picks that tier; cache
# read = 10% of the input rate; cache write = 125% of the input rate; any other
# model id is priced at the sonnet rate and flagged as estimated
# (models_unknown in cost.json). Streamed duplicates (same message.id) count once.
#
# Budget: env MOGGER_BUDGET_USD (dollars). Unset, 0, or not a number = feature
# OFF (default OFF, exit 0 immediately).
#   >= 80% : allow, print a one-time warning to stderr, AND record it as
#            "warning" in .claude/state/cost.json (stderr on exit 0 may not be
#            shown; session-start / STATUS.md surface the file instead).
#   >= 100%: block (exit 2) telling the Lead to stop and tell the user.
# Escape: MOGGER_BUDGET_OVERRIDE=on lets everything through (state still written).
#
# Writes .claude/state/cost.json each recompute:
#   {spent_usd, budget_usd, pct, estimated:true, models:{model:usd}, ts, ...}
# Recompute is throttled to once per 20 s (cost.json mtime) so big
# transcripts stay cheap; a changed budget bypasses the throttle.
#
# FAILS OPEN (exit 0) if: no budget, no python3 (verified to really run, not the
# Windows Store stub), transcript missing/unreadable, pricing.json missing, or
# any internal error. Needs python3 only; bash 3.2 compatible.
source "$(dirname "$0")/lib.sh"

INPUT=$(cat)

BUDGET="${MOGGER_BUDGET_USD:-}"
case "$BUDGET" in ""|0|0.0|0.00) exit 0 ;; esac
case "$BUDGET" in *[!0-9.]*|*.*.*|.) exit 0 ;; esac

command -v python3 >/dev/null 2>&1 && python3 -c '1' >/dev/null 2>&1 || exit 0

TRANSCRIPT=$(json_get "$INPUT" '.transcript_path')
[ -n "$TRANSCRIPT" ] && [ -r "$TRANSCRIPT" ] || exit 0

PRICING="${MOGGER_PRICING_FILE:-$(cd "$(dirname "$0")/../.." && pwd)/templates/pricing.json}"
[ -r "$PRICING" ] || exit 0

STATE_DIR=".claude/state"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

RESULT=$(python3 - "$TRANSCRIPT" "$PRICING" "$BUDGET" "$STATE_DIR/cost.json" <<'PY' 2>/dev/null
import sys, os, json, time
from fractions import Fraction
from datetime import datetime, timezone

tpath, ppath, budget_s, cpath = sys.argv[1:5]
try:
    budget = Fraction(budget_s)
    if budget <= 0:
        print("OFF"); sys.exit(0)
except Exception:
    print("OFF"); sys.exit(0)

def load(p):
    try:
        with open(p) as f: return json.load(f)
    except Exception: return None

cached = load(cpath)
now = time.time()
fresh = False
if cached and cached.get("transcript") == tpath and "spent_exact" in cached:
    try:
        fresh = (now - os.path.getmtime(cpath) < 20) and Fraction(str(cached.get("budget_usd"))) == budget
    except Exception: fresh = False

if fresh:
    spent = Fraction(cached["spent_exact"])
    print("OK" if spent < budget * Fraction(4, 5) else ("WARN_CACHED" if spent < budget else "BLOCK"), float(spent), float(budget))
    sys.exit(0)

pricing = load(ppath)
rates = {}
for tier, r in (pricing or {}).get("models", {}).items():
    rates[tier] = (Fraction(str(r["input_per_mtok"])), Fraction(str(r["output_per_mtok"])))
if "sonnet" not in rates:
    print("OFF"); sys.exit(0)

usage_by_key = {}   # dedupe streamed duplicates by message id; keep last
order = []
with open(tpath, errors="replace") as f:
    for i, line in enumerate(f):
        line = line.strip()
        if not line: continue
        try: e = json.loads(line)
        except Exception: continue
        m = e.get("message") if isinstance(e, dict) else None
        if not isinstance(m, dict) or e.get("type", "assistant") != "assistant": continue
        u = m.get("usage")
        if not isinstance(u, dict): continue
        key = m.get("id") or ("line%d" % i)
        if key not in usage_by_key: order.append(key)
        usage_by_key[key] = (str(m.get("model") or ""), u)

models = {}; unknown = set(); total = Fraction(0)
def n(u, k):
    v = u.get(k, 0)
    return int(v) if isinstance(v, (int, float)) else 0
for key in order:
    model, u = usage_by_key[key]
    low = model.lower()
    tier = next((t for t in ("haiku", "sonnet", "opus") if t in low and t in rates), None)
    if tier is None:
        if low == "<synthetic>": continue
        tier = "sonnet"; unknown.add(model or "(none)")
    rin, rout = rates[tier]
    cost = (Fraction(n(u, "input_tokens")) * rin + Fraction(n(u, "output_tokens")) * rout
            + Fraction(n(u, "cache_read_input_tokens")) * rin / 10
            + Fraction(n(u, "cache_creation_input_tokens")) * rin * Fraction(5, 4)) / 1000000
    label = model or "(none)"
    models[label] = models.get(label, Fraction(0)) + cost
    total += cost

warned_before = bool(cached and cached.get("warned") and Fraction(str(cached.get("budget_usd"))) == budget) if cached else False
status = "OK"; warning = ""
if total >= budget:
    status = "BLOCK"
    warning = "Budget reached: about $%.2f of $%s (estimated)." % (float(total), budget_s)
elif total >= budget * Fraction(4, 5):
    status = "WARN" if not warned_before else "WARN_CACHED"
    warning = "Over 80%% of budget: about $%.2f of $%s (estimated)." % (float(total), budget_s)

state = {
    "spent_usd": round(float(total), 6), "budget_usd": float(budget),
    "pct": round(float(total / budget * 100), 1), "estimated": True,
    "models": {k: round(float(v), 6) for k, v in models.items()},
    "models_unknown": sorted(unknown),
    "warning": warning, "warned": bool(warning) and (status != "OK"),
    "spent_exact": str(total), "transcript": tpath,
    "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}
try:
    tmp = cpath + ".tmp.%d" % os.getpid()
    with open(tmp, "w") as f: json.dump(state, f)
    os.replace(tmp, cpath)
except Exception: pass
print(status, float(total), float(budget))
PY
)

set -- $RESULT
STATUS="${1:-}"; SPENT="${2:-0}"
case "$STATUS" in
  BLOCK)
    [ "${MOGGER_BUDGET_OVERRIDE:-off}" = "on" ] && exit 0
    printf 'Budget $%s reached ($%s spent, estimated from transcript). Stop and tell the user; they can raise MOGGER_BUDGET_USD.\n' \
      "$BUDGET" "$(printf '%.2f' "$SPENT" 2>/dev/null || printf '%s' "$SPENT")" >&2
    exit 2 ;;
  WARN)
    printf 'mogger: over 80%% of the $%s budget ($%s spent, estimated from transcript). Continuing; raise MOGGER_BUDGET_USD or wrap up.\n' \
      "$BUDGET" "$(printf '%.2f' "$SPENT" 2>/dev/null || printf '%s' "$SPENT")" >&2
    exit 0 ;;
esac
exit 0
