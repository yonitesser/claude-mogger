from renewals.dates import add_months


def renewal_dates(start, count):
    """The first `count` billing dates of a subscription that started on `start`, one per month,
    starting with `start` itself."""
    dates = [start]
    current = start
    for _ in range(count - 1):
        current = add_months(current, 1)
        dates.append(current)
    return dates


def next_renewal(start, today):
    """The first billing date strictly after `today`."""
    n = 1
    while True:
        d = renewal_dates(start, n + 1)[-1]
        if d > today:
            return d
        n += 1
