def to_cents(amount):
    """Convert a decimal string to whole cents, half up."""
    whole, _, frac = amount.partition(".")
    frac = (frac + "00")[:2]
    return int(whole) * 100 + int(frac)
