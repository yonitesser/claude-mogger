from renewals.dates import add_months


def renewal_dates(start, count):
    """The first `count` billing dates of a subscription that started on `start`, one per month,
    starting with `start` itself. Every date is computed from `start`, so a month-end sign-up
    does not drift (Jan 31, Feb 28, Mar 31)."""
    return [add_months(start, i) for i in range(count)]


def next_renewal(start, today):
    """The first billing date strictly after `today`."""
    n = 1
    while True:
        d = add_months(start, n)
        if d > today:
            return d
        n += 1
