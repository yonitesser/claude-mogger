"""Price calculation."""


def price(base_cents, quantity):
    return base_cents * quantity


def with_tax(cents, rate=0.2):
    return int(round(cents * (1 + rate)))
