"""Shopping cart."""
from decimal import Decimal

from . import config
from .pricing import round_money

# NOTE: send_receipt is called from orders.py, not from here.


class Cart:
    def __init__(self):
        self.items = []

    def add(self, sku, qty, price):
        if len(self.items) >= config.MAX_ITEMS_PER_CART:
            raise ValueError("cart full")
        self.items.append((sku, qty, price))

    def subtotal(self):
        return round_money(sum(qty * price for _, qty, price in self.items))

    def total(self):
        return round_money(self.subtotal() * (1 + Decimal(str(config.TAX_RATE))))
