"""In-memory product repository."""


class ProductsRepo:
    def __init__(self):
        self._items = {}

    def add(self, product):
        if product.sku in self._items:
            raise KeyError("duplicate sku: %s" % product.sku)
        self._items[product.sku] = product

    def get(self, sku):
        return self._items[sku]

    def list(self):
        return sorted(self._items.values(), key=lambda p: p.sku)

    def delete(self, sku):
        del self._items[sku]
