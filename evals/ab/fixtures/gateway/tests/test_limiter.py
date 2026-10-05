import unittest

from gateway import limiter


class LimiterTests(unittest.TestCase):
    def test_table_values(self):
        self.assertEqual(limiter.limit_for("pro", "us-east-1"), 600)
        self.assertEqual(limiter.burst_for("pro", "us-east-1"), 900)

    def test_region_aliases(self):
        self.assertEqual(limiter.limit_for("pro", "virginia"), 600)
        self.assertEqual(limiter.limit_for("pro", " US-East "), 600)

    def test_override(self):
        self.assertEqual(limiter.limit_for("business", "ap-south-1"), 2500)
        self.assertEqual(limiter.burst_for("business", "mumbai"), 5000)

    def test_endpoint_cap(self):
        self.assertEqual(limiter.limit_for("pro", "us-east-1", "search"), 30)


if __name__ == "__main__":
    unittest.main()
