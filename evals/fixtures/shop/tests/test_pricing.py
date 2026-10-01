import unittest
from decimal import Decimal

from shop.pricing import apply_discount, round_money


class PricingTests(unittest.TestCase):
    def test_round_half_up(self):
        self.assertEqual(round_money("2.675"), Decimal("2.68"))

    def test_discount_clamped(self):
        self.assertEqual(apply_discount("10", 150), Decimal("0.00"))


if __name__ == "__main__":
    unittest.main()
