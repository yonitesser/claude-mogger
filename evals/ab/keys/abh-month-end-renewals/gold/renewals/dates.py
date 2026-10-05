import calendar
from datetime import date


def add_months(d, months):
    """The date `months` calendar months after d (months may be negative).
    When the target month is shorter, the last day of that month is used."""
    y, m = divmod(d.month - 1 + months, 12)
    year, month = d.year + y, m + 1
    return date(year, month, min(d.day, calendar.monthrange(year, month)[1]))
