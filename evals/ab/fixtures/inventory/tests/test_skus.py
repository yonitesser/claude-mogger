import unittest

from inventory import skus


class SkuTests(unittest.TestCase):
    def test_clean(self):
        self.assertEqual(skus.clean_sku("  ab-1 "), "AB-1")

    def test_valid(self):
        self.assertTrue(skus.is_valid_sku("AB-1"))
        self.assertFalse(skus.is_valid_sku("ab 1"))


if __name__ == "__main__":
    unittest.main()
