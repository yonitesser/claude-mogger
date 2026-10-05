from datetime import date


def add_months(d, months):
    """The date `months` calendar months after d (months may be negative)."""
    y, m = divmod(d.month - 1 + months, 12)
    return date(d.year + y, m + 1, d.day)
