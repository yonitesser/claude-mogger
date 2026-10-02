import unittest

from shop import export, ledger, receipt
from shop.cart import Cart


def odd():
    c = Cart()
    for sku in "abc":
        c.add(sku, 333)
    c.apply_coupon(10)
    return c


class CouponTests(unittest.TestCase):
    def test_total(self):
        self.assertEqual(odd().total_cents(), 899)

    def test_ledger_balances(self):
        self.assertEqual(sum(c for _a, c in ledger.entries(odd())), 899)

    def test_export(self):
        d = export.to_dict(odd())
        self.assertEqual(sum(x["line_cents"] for x in d["lines"]), 899)
        self.assertEqual(d["discount_cents"], 100)

    def test_receipt(self):
        self.assertIn("Discount (10%): -$1.00", receipt.render(odd()))

    def test_bad_percent(self):
        with self.assertRaises(ValueError):
            Cart().apply_coupon(0)
