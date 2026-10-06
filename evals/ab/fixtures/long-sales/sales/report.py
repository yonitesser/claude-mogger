"""Revenue report."""


def by_month(orders):
    out = {}
    for o in orders:
        key = o.date[:7]
        out[key] = out.get(key, 0) + o.amount_cents
    return dict(sorted(out.items()))


def money(cents):
    sign = "-" if cents < 0 else ""
    cents = abs(cents)
    return "%s$%s.%02d" % (sign, "{:,}".format(cents // 100), cents % 100)


def render(orders):
    lines = ["Revenue by month"]
    for month, cents in by_month(orders).items():
        lines.append("  %s  %s" % (month, money(cents)))
    lines.append("  total    %s" % money(sum(o.amount_cents for o in orders)))
    return "\n".join(lines)
