#!/usr/bin/env bash
# Prints .claude/state/cost.json (written by hooks/scripts/cost-cap.sh) in plain words.
# The number is an ESTIMATE: token counts x published rates (templates/pricing.json).
# Usage: bash scripts/cost-report.sh [path/to/cost.json]
F="${1:-.claude/state/cost.json}"
if [ ! -f "$F" ]; then
  echo "No cost data yet. The cost cap is off unless MOGGER_BUDGET_USD is set (for example: export MOGGER_BUDGET_USD=5)."
  exit 0
fi
if command -v python3 >/dev/null 2>&1 && python3 -c '1' >/dev/null 2>&1; then
  python3 - "$F" <<'PY'
import sys, json
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print("cost.json is unreadable."); sys.exit(0)
print("Spent so far: about $%.2f of a $%.2f budget (%s%%)." % (d.get("spent_usd", 0), d.get("budget_usd", 0), d.get("pct", "?")))
print("This is an estimate from token counts x published rates, not a bill.")
for m, v in sorted((d.get("models") or {}).items(), key=lambda kv: -kv[1]):
    print("  %-32s $%.2f" % (m, v))
if d.get("models_unknown"):
    print("Priced at the sonnet rate (unknown model): " + ", ".join(d["models_unknown"]))
if d.get("warning"): print("Warning: " + d["warning"])
print("Last updated: " + str(d.get("ts", "?")))
PY
else
  sp=$(sed -n 's/.*"spent_usd": *\([0-9.]*\).*/\1/p' "$F"); bu=$(sed -n 's/.*"budget_usd": *\([0-9.]*\).*/\1/p' "$F")
  pc=$(sed -n 's/.*"pct": *\([0-9.]*\).*/\1/p' "$F")
  echo "Spent so far: about \$$sp of a \$$bu budget ($pc%). Estimate from token counts x published rates."
fi
exit 0
