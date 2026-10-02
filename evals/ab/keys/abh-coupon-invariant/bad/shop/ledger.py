"""Accounting entries for a cart.

Rule of the books: the entries of one cart must add up to exactly cart.total_cents(),
to the cent. entries() refuses to return anything that does not.
"""


class LedgerError(Exception):
    pass


def assert_balanced(entries, cart):
    got = sum(cents for _account, cents in entries)
    if got != cart.total_cents():
        raise LedgerError("entries add up to %d but the cart total is %d" % (got, cart.total_cents()))


def entries(cart):
    out = []
    for (sku, _unit, _qty), cents in zip(cart.lines, cart.net_line_cents()):
        out.append(("sales:" + sku, cents))
    assert_balanced(out, cart)
    return out
