"""Load and aggregate sales rows."""
import csv


def load(path):
    rows = []
    with open(path, newline="") as f:
        for r in csv.DictReader(f):
            rows.append({"region": r["region"], "product": r["product"],
                         "qty": int(r["qty"]), "revenue": float(r["revenue"])})
    return rows


def by_region(rows):
    """Return a list of {'region', 'orders', 'qty', 'revenue'} sorted by region name."""
    acc = {}
    for r in rows:
        a = acc.setdefault(r["region"], {"region": r["region"], "orders": 0, "qty": 0, "revenue": 0.0})
        a["orders"] += 1
        a["qty"] += r["qty"]
        a["revenue"] = round(a["revenue"] + r["revenue"], 2)
    return [acc[k] for k in sorted(acc)]
