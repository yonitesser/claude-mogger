def to_dict(cart):
    lines = []
    for sku, unit, qty in cart.lines:
        lines.append({"sku": sku, "qty": qty, "unit_cents": unit, "line_cents": unit * qty})
    return {"lines": lines, "total_cents": cart.total_cents()}
