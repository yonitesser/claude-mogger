def to_dict(cart):
    lines = []
    for (sku, unit, qty), cents in zip(cart.lines, cart.net_line_cents()):
        lines.append({"sku": sku, "qty": qty, "unit_cents": unit, "line_cents": cents})
    return {"lines": lines, "total_cents": cart.total_cents(),
            "coupon_percent": cart.coupon_percent, "discount_cents": cart.discount_cents()}
