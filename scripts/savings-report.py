#!/usr/bin/env python3
"""
Reads .claude/state/savings.jsonl and prints/renders an ESTIMATE of cost
avoided by routing work to a cheaper model, using published per-token
pricing. This is NOT a comparison against a real counterfactual run — no
task in this log was ever actually run twice. It's a disclosed calculation:
"this output's length, billed at the Lead's model rate instead of the
routed model's rate, would have cost $X; it actually cost $Y; the delta
is the estimate." Token counts are a chars/4 heuristic, not a real
tokenizer count. Both approximations are stated in the report itself —
this script never hides its own methodology.

Usage: python3 scripts/savings-report.py [--lead-model sonnet|opus]
Env:   MOGGER_LEAD_MODEL overrides the default lead model (sonnet).
"""
import json, os, sys, pathlib, datetime

ROOT = pathlib.Path(__file__).resolve().parent.parent
LOG = pathlib.Path(".claude/state/savings.jsonl")
PRICING_CANDIDATES = [pathlib.Path("pricing.json"), ROOT / "templates" / "pricing.json"]

def load_pricing():
    for p in PRICING_CANDIDATES:
        if p.exists():
            return json.loads(p.read_text()), p
    sys.exit("No pricing.json found (checked ./pricing.json and templates/pricing.json).")

def chars_to_tokens(chars):
    return chars / 4.0  # heuristic, not a real tokenizer — stated in every report

def cost(model, rates, in_chars, out_chars):
    m = rates["models"].get(model)
    if not m:
        return None
    in_tok = chars_to_tokens(in_chars) / 1_000_000
    out_tok = chars_to_tokens(out_chars) / 1_000_000
    return in_tok * m["input_per_mtok"] + out_tok * m["output_per_mtok"]

def main():
    lead_model = os.environ.get("MOGGER_LEAD_MODEL", "sonnet")
    if len(sys.argv) > 2 and sys.argv[1] == "--lead-model":
        lead_model = sys.argv[2]

    rates, rates_path = load_pricing()
    if not LOG.exists():
        print(f"No {LOG} yet — nothing has been logged. This is normal on a fresh project;")
        print("it fills in as bulk-reader/explorer/code-writer/tester agents run and self-report.")
        return

    rows = []
    for line in LOG.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError:
            continue

    if not rows:
        print(f"{LOG} exists but has no valid entries yet.")
        return

    by_agent = {}
    total_actual = 0.0
    total_hypothetical = 0.0
    for r in rows:
        model = r.get("model", "haiku")
        in_c, out_c = r.get("input_chars", 0), r.get("output_chars", 0)
        actual = cost(model, rates, in_c, out_c) or 0.0
        hypothetical = cost(lead_model, rates, in_c, out_c) or 0.0
        avoided = max(0.0, hypothetical - actual)  # never claim negative "savings"
        total_actual += actual
        total_hypothetical += hypothetical
        a = by_agent.setdefault(r.get("agent", "unknown"), {"calls": 0, "actual": 0.0, "avoided": 0.0})
        a["calls"] += 1
        a["actual"] += actual
        a["avoided"] += avoided

    total_avoided = max(0.0, total_hypothetical - total_actual)

    print(f"Pricing source: {rates_path} (as_of: {rates.get('as_of', 'unknown')} — verify at https://claude.com/pricing)")
    print(f"Lead model used for comparison: {lead_model} (override with MOGGER_LEAD_MODEL or --lead-model)")
    print(f"Token counts: chars/4 estimate, not a real tokenizer — treat as directional, not exact.")
    print()
    print(f"{'agent':<14} {'calls':>6} {'actual $':>10} {'avoided $ (est.)':>18}")
    for agent, d in sorted(by_agent.items(), key=lambda kv: -kv[1]["avoided"]):
        print(f"{agent:<14} {d['calls']:>6} {d['actual']:>10.4f} {d['avoided']:>18.4f}")
    print(f"{'TOTAL':<14} {len(rows):>6} {total_actual:>10.4f} {total_avoided:>18.4f}")
    print()
    print("This is an estimate of avoided spend from model routing, not a comparison")
    print("to a session that was actually re-run without this kit. See README for the")
    print("full methodology disclosure.")

    write_dashboard(by_agent, total_actual, total_avoided, lead_model, rates.get("as_of", "unknown"))

def write_dashboard(by_agent, total_actual, total_avoided, lead_model, as_of):
    agents = sorted(by_agent.items(), key=lambda kv: -kv[1]["avoided"])
    max_avoided = max((d["avoided"] for _, d in agents), default=1.0) or 1.0
    bars = ""
    for agent, d in agents:
        pct = (d["avoided"] / max_avoided) * 100
        bars += f'''
        <div class="row">
          <div class="label">{agent} <span class="calls">({d["calls"]} calls)</span></div>
          <div class="track"><div class="bar" style="width:{pct:.1f}%"></div></div>
          <div class="value">${d["avoided"]:.4f}</div>
        </div>'''

    html = f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>mogger savings estimate</title>
<style>
  body {{ font-family: -apple-system, sans-serif; max-width: 720px; margin: 40px auto; color: #1a1a1a; }}
  h1 {{ font-size: 20px; }}
  .disclaimer {{ background: #fff8e1; border: 1px solid #f0d878; padding: 12px 16px; border-radius: 6px; font-size: 13px; margin-bottom: 24px; }}
  .total {{ font-size: 32px; font-weight: 700; margin: 8px 0 24px; }}
  .row {{ display: flex; align-items: center; gap: 12px; margin-bottom: 10px; }}
  .label {{ width: 160px; font-size: 13px; }}
  .calls {{ color: #888; }}
  .track {{ flex: 1; background: #eee; border-radius: 4px; overflow: hidden; height: 20px; }}
  .bar {{ background: #2563eb; height: 100%; }}
  .value {{ width: 90px; text-align: right; font-variant-numeric: tabular-nums; font-size: 13px; }}
  footer {{ margin-top: 32px; font-size: 12px; color: #888; }}
</style></head>
<body>
  <h1>mogger — estimated cost avoided by model routing</h1>
  <div class="disclaimer">
    <strong>What this is:</strong> an estimate of what routed calls (Haiku)
    would have cost if billed at the {lead_model} rate instead, for the
    actual output length produced. <strong>What this isn't:</strong> a
    comparison to a real session run without this kit — no task here was
    ever run twice. Token counts are a chars/4 heuristic, not an exact
    tokenizer count. Pricing snapshot as of {as_of} — verify current rates
    at claude.com/pricing.
  </div>
  <div>Total estimated avoided spend</div>
  <div class="total">${total_avoided:.4f}</div>
  <div>Total actual spend (routed calls only): ${total_actual:.4f}</div>
  <h3>By agent</h3>
  {bars if bars else '<p>No data yet.</p>'}
  <footer>Generated {datetime.datetime.now(datetime.timezone.utc).isoformat()}Z by scripts/savings-report.py</footer>
</body></html>"""
    out = pathlib.Path("savings-dashboard.html")
    out.write_text(html)
    print(f"\nDashboard written to {out} — open it in a browser.")

if __name__ == "__main__":
    main()
