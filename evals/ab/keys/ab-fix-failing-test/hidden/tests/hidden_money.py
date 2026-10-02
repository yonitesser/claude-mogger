import unittest

from billing import invoice as inv


class HiddenMoneyTests(unittest.TestCase):
    def test_half_cent_rounds_up(self):
        self.assertEqual(inv.money(0.125), 0.13)
        self.assertEqual(inv.money(1.005), 1.01)
        self.assertEqual(inv.money(2.675), 2.68)

    def test_reduced_tax_cases(self):
        self.assertEqual(inv.tax_amount(2.50, "reduced"), 0.13)
        self.assertEqual(inv.tax_amount(7.10, "reduced"), 0.36)

    def test_line_total_half_cent(self):
        self.assertEqual(inv.line_total({"sku": "a", "qty": 3, "unit_price": 0.835}), 2.51)

    def test_discount_half_cent(self):
        self.assertEqual(inv.discount_amount(1.05, "BULK"), 0.16)

    def test_values_unchanged_elsewhere(self):
        self.assertEqual(inv.money(1.234), 1.23)
        self.assertEqual(inv.money(10), 10.0)
        self.assertEqual(inv.tax_amount(100.0, "standard"), 8.25)
        self.assertEqual(inv.format_money(3.1), "$3.10")


if __name__ == "__main__":
    unittest.main()
