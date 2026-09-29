import unittest

from shop.billing.parser import parse_invoice


class BillingTests(unittest.TestCase):
    def test_parse_two_lines(self):
        rows = parse_invoice("AB-1 2 3.50\n\nCD-2 1 9.99\n")
        self.assertEqual([r["sku"] for r in rows], ["AB-1", "CD-2"])


if __name__ == "__main__":
    unittest.main()
