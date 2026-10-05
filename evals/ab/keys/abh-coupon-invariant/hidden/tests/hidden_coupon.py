import unittest

from shop import export, ledger, receipt
from shop.cart import Cart


def cart_of(amounts, pct=None):
    c = Cart()
    for i, a in enumerate(amounts):
        c.add("s%d" % i, a)
    if pct is not None:
        c.apply_coupon(pct)
    return c


class HiddenCouponTests(unittest.TestCase):
    def test_no_coupon_is_unchanged(self):
        c = cart_of([333, 333, 333])
        self.assertEqual(c.total_cents(), 999)
        self.assertEqual([x for _a, x in ledger.entries(c)], [333, 333, 333])
        self.assertNotIn("Discount", receipt.render(c))

    def test_discount_rounds_half_up_not_to_even(self):
        c = cart_of([50], 1)
        self.assertEqual(c.total_cents(), 49)
        c = cart_of([250], 10)
        self.assertEqual(c.total_cents(), 225)
        c = cart_of([999], 10)
        self.assertEqual(c.total_cents(), 899)

    def test_ledger_adds_up_to_total_on_awkward_carts(self):
        for amounts, pct in (([333, 333, 333], 10), ([101, 101, 101, 101], 15), ([1, 1, 1], 50), ([999, 1, 5], 33), ([7, 7, 7, 7, 7], 5)):
            c = cart_of(amounts, pct)
            self.assertEqual(sum(x for _a, x in ledger.entries(c)), c.total_cents(), (amounts, pct))

    def test_export_lines_add_up_and_stay_close_to_exact(self):
        for amounts, pct in (([333, 333, 333], 10), ([101, 101, 101, 101], 15), ([999, 1, 5], 33)):
            c = cart_of(amounts, pct)
            d = export.to_dict(c)
            self.assertEqual(sum(x["line_cents"] for x in d["lines"]), d["total_cents"])
            self.assertEqual(d["total_cents"], c.total_cents())
            self.assertEqual(d["discount_cents"], sum(amounts) - c.total_cents())
            self.assertEqual(d["coupon_percent"], pct)
            for x, gross in zip(d["lines"], amounts):
                self.assertTrue(0 <= x["line_cents"] <= gross)
                self.assertLessEqual(abs(x["line_cents"] * 100 - gross * (100 - pct)), 100)
            for _acct, cents in ledger.entries(c):
                self.assertGreaterEqual(cents, 0)

    def test_ledger_and_export_agree_line_by_line(self):
        c = cart_of([333, 333, 333], 10)
        self.assertEqual([x for _a, x in ledger.entries(c)], [x["line_cents"] for x in export.to_dict(c)["lines"]])

    def test_receipt_lines(self):
        txt = receipt.render(cart_of([333, 333, 333], 10))
        self.assertIn("Discount (10%): -$1.00", txt)
        self.assertTrue(txt.endswith("TOTAL  $8.99"))
        self.assertLess(txt.index("Discount"), txt.index("TOTAL"))

    def test_coupon_replaces_and_validates(self):
        c = cart_of([1000], 10)
        c.apply_coupon(20)
        self.assertEqual(c.total_cents(), 800)
        c.apply_coupon(100)
        self.assertEqual(c.total_cents(), 0)
        self.assertEqual(ledger.entries(c), [("sales:s0", 0)])
        for bad in (0, 101, -5, 12.5, "10", True, None):
            with self.assertRaises(ValueError, msg=repr(bad)):
                c.apply_coupon(bad)
        self.assertEqual(c.total_cents(), 0)


if __name__ == "__main__":
    unittest.main()
