"""Price maths. All money is Decimal."""
from decimal import Decimal, ROUND_HALF_UP


def round_money(value):
    """Round to cents, half up."""
    return Decimal(value).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def apply_discount(price, percent):
    """Return price reduced by percent. Percent is clamped to 0..100."""
    percent = max(0, min(100, percent))
    return round_money(Decimal(price) * (Decimal(100) - Decimal(percent)) / Decimal(100))
