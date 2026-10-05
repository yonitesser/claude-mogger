from shop.money import fmt


def render(cart):
    out = []
    for sku, unit, qty in cart.lines:
        out.append("%s x%d  %s" % (sku, qty, fmt(unit * qty)))
    out.append("TOTAL  %s" % fmt(cart.total_cents()))
    return "\n".join(out)
