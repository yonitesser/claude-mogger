import unittest
from decimal import Decimal

from shop.cart import Cart


class CartTests(unittest.TestCase):
    def test_empty_cart_total_is_zero(self):
        self.assertEqual(Cart().total(), Decimal("0.00"))

    def test_add_and_subtotal(self):
        c = Cart()
        c.add("A", 2, Decimal("1.50"))
        self.assertEqual(c.subtotal(), Decimal("3.00"))

    def test_full_cart_raises(self):
        c = Cart()
        for i in range(50):
            c.add("S%d" % i, 1, Decimal("1"))
        with self.assertRaises(ValueError):
            c.add("X", 1, Decimal("1"))


if __name__ == "__main__":
    unittest.main()
