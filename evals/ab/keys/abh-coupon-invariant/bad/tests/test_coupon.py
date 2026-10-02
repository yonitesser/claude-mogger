import unittest

from shop import export, ledger, receipt
from shop.cart import Cart


def simple():
    c = Cart()
    c.add("a", 1000)
    c.add("b", 500, 2)
    c.apply_coupon(10)
    return c


class CouponTests(unittest.TestCase):
    def test_total(self):
        self.assertEqual(simple().total_cents(), 1800)

    def test_ledger(self):
        self.assertEqual(sum(c for _a, c in ledger.entries(simple())), 1800)

    def test_export(self):
        self.assertEqual(export.to_dict(simple())["discount_cents"], 200)

    def test_receipt(self):
        self.assertIn("Discount (10%): -$2.00", receipt.render(simple()))

    def test_bad_percent(self):
        with self.assertRaises(ValueError):
            Cart().apply_coupon(0)
