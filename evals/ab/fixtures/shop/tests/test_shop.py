import unittest

from shop import export, ledger, receipt
from shop.cart import Cart


def sample():
    c = Cart()
    c.add("pen", 250, 2)
    c.add("ink", 1999)
    return c


class CartTests(unittest.TestCase):
    def test_totals(self):
        self.assertEqual(sample().subtotal_cents(), 2499)
        self.assertEqual(sample().total_cents(), 2499)

    def test_bad_qty(self):
        with self.assertRaises(ValueError):
            Cart().add("x", 100, 0)

    def test_receipt(self):
        self.assertEqual(receipt.render(sample()), "pen x2  $5.00\nink x1  $19.99\nTOTAL  $24.99")

    def test_ledger(self):
        self.assertEqual(ledger.entries(sample()), [("sales:pen", 500), ("sales:ink", 1999)])

    def test_export(self):
        d = export.to_dict(sample())
        self.assertEqual(d["total_cents"], 2499)
        self.assertEqual([x["line_cents"] for x in d["lines"]], [500, 1999])


if __name__ == "__main__":
    unittest.main()
