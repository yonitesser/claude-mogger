"""Shipping cost by weight tier."""


def shipping_cost(weight_kg):
    """Cost in whole euros. 0 < w <= 1: 4; 1 < w <= 5: 9; 5 < w <= 20: 25. Otherwise ValueError."""
    if weight_kg <= 0 or weight_kg > 20:
        raise ValueError("weight out of range")
    if weight_kg <= 1:
        return 4
    if weight_kg <= 5:
        return 9
    return 25
