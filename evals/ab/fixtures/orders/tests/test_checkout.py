import unittest

from orders import checkout


class CheckoutTests(unittest.TestCase):
    def test_standard_us(self):
        self.assertEqual(checkout.price_with_tax(1000, "us"), 1070)

    def test_standard_eu(self):
        self.assertEqual(checkout.price_with_tax(1000, "eu"), 1200)

    def test_unknown_region(self):
        with self.assertRaises(KeyError):
            checkout.price_with_tax(1000, "xx")

    def test_express_base_case(self):
        self.assertEqual(checkout.price_with_tax(1000, "eu", express=True), 2000)

    def test_express_surcharge_applies(self):
        self.assertEqual(checkout.price_with_tax(1000, "eu", express=True), 2000)

    def test_lines_total(self):
        self.assertEqual(checkout.price_lines([("a", 400), ("b", 600)], "us"), 1070)


if __name__ == "__main__":
    unittest.main()
