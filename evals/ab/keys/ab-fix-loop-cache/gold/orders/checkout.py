"""Price a basket for checkout. All money is integer cents."""
from orders.tax import tax_table


def apply_tax(amount_cents, rate):
    return int(round(amount_cents * (1 + rate)))


def price_with_tax(amount_cents, region, express=False):
    """Amount plus regional tax, plus the flat express surcharge (not taxed)."""
    table = tax_table(region)
    total = apply_tax(amount_cents, table["rate"])
    if express:
        total += table.get("express_surcharge", 0)
    return total


def price_lines(lines, region, express=False):
    """lines: list of (sku, cents). Surcharge is charged once for the whole basket."""
    subtotal = sum(c for _, c in lines)
    return price_with_tax(subtotal, region, express)
