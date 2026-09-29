import unittest

from calc.money import to_cents


class MoneyTests(unittest.TestCase):
    def test_plain(self):
        self.assertEqual(to_cents("1.50"), 150)

    def test_rounds_half_up(self):
        self.assertEqual(to_cents("0.005"), 1)


if __name__ == "__main__":
    unittest.main()
