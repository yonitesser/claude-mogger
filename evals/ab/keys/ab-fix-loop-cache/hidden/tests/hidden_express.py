import unittest

from orders import checkout, tax


class HiddenExpressTests(unittest.TestCase):
    def test_repeated_express_calls_agree(self):
        first = checkout.price_with_tax(1000, "eu", express=True)
        for _ in range(3):
            self.assertEqual(checkout.price_with_tax(1000, "eu", express=True), first)
        self.assertEqual(first, 2000)

    def test_other_regions_and_mixed_calls(self):
        self.assertEqual(checkout.price_with_tax(1000, "us", express=True), 1570)
        self.assertEqual(checkout.price_with_tax(1000, "us"), 1070)
        self.assertEqual(checkout.price_with_tax(1000, "us", express=True), 1570)
        self.assertEqual(checkout.price_with_tax(1000, "jp", express=True), 2000)

    def test_table_keeps_its_surcharge(self):
        checkout.price_with_tax(1000, "uk", express=True)
        self.assertIn("express_surcharge", tax.tax_table("uk"))

    def test_lines_express_charged_once(self):
        lines = [("a", 400), ("b", 600)]
        self.assertEqual(checkout.price_lines(lines, "eu", express=True), 2000)
        self.assertEqual(checkout.price_lines(lines, "eu", express=True), 2000)


if __name__ == "__main__":
    unittest.main()
