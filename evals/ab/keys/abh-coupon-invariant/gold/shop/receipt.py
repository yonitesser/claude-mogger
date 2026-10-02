from shop.money import fmt


def render(cart):
    out = []
    for sku, unit, qty in cart.lines:
        out.append("%s x%d  %s" % (sku, qty, fmt(unit * qty)))
    if cart.coupon_percent:
        out.append("Discount (%d%%): %s" % (cart.coupon_percent, fmt(-cart.discount_cents())))
    out.append("TOTAL  %s" % fmt(cart.total_cents()))
    return "\n".join(out)
