"""Revenue report. Revenue is after refunds: refunded shop orders count 0, legacy refund rows are
negative amounts. Test orders (customer email at example.com) never count."""
import json


def by_month(orders):
    out = {}
    for o in orders:
        key = o.date[:7]
        out[key] = out.get(key, 0) + o.amount_cents
    return dict(sorted(out.items()))


def is_test_order(order):
    return order.email.strip().lower().endswith("@example.com")


def revenue_orders(orders):
    return [o for o in orders if o.status != "refunded" and not is_test_order(o)]


def top_categories(orders, n=5):
    totals = {}
    for o in orders:
        totals[o.category] = totals.get(o.category, 0) + o.amount_cents
    ranked = sorted(totals.items(), key=lambda kv: (-kv[1], kv[0]))
    return ranked[:n]


def money(cents):
    sign = "-" if cents < 0 else ""
    cents = abs(cents)
    return "%s$%s.%02d" % (sign, "{:,}".format(cents // 100), cents % 100)


def render(orders):
    orders = revenue_orders(orders)
    lines = ["Revenue by month (after refunds)"]
    for month, cents in by_month(orders).items():
        lines.append("  %s  %s" % (month, money(cents)))
    lines.append("  total    %s" % money(sum(o.amount_cents for o in orders)))
    lines.append("Top categories")
    for category, cents in top_categories(orders):
        lines.append("  %-12s %s" % (category, money(cents)))
    return "\n".join(lines)


def render_json(orders):
    orders = revenue_orders(orders)
    return json.dumps({
        "months": dict((m, c / 100) for m, c in by_month(orders).items()),
        "top_categories": [{"category": cat, "revenue": c / 100} for cat, c in top_categories(orders)],
    })
