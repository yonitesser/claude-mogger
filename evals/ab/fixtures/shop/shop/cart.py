class Cart:
    def __init__(self):
        self.lines = []  # each line is [sku, unit_cents, qty]

    def add(self, sku, unit_cents, qty=1):
        if qty < 1:
            raise ValueError("qty must be at least 1")
        self.lines.append([sku, unit_cents, qty])

    def subtotal_cents(self):
        return sum(unit * qty for _sku, unit, qty in self.lines)

    def total_cents(self):
        return self.subtotal_cents()
