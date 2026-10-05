class Cart:
    def __init__(self):
        self.lines = []  # each line is [sku, unit_cents, qty]
        self.coupon_percent = 0

    def add(self, sku, unit_cents, qty=1):
        if qty < 1:
            raise ValueError("qty must be at least 1")
        self.lines.append([sku, unit_cents, qty])

    def apply_coupon(self, percent):
        if not 1 <= percent <= 100:
            raise ValueError("percent must be from 1 to 100")
        self.coupon_percent = percent

    def subtotal_cents(self):
        return sum(unit * qty for _sku, unit, qty in self.lines)

    def discount_cents(self):
        return round(self.subtotal_cents() * self.coupon_percent / 100)

    def total_cents(self):
        return self.subtotal_cents() - self.discount_cents()

    def net_line_cents(self):
        return [round(unit * qty * (100 - self.coupon_percent) / 100) for _sku, unit, qty in self.lines]
