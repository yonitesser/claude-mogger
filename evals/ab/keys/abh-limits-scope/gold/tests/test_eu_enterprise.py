import unittest

from gateway import limiter


class EuEnterpriseTests(unittest.TestCase):
    def test_raised(self):
        self.assertEqual(limiter.limit_for("enterprise", "eu-west"), 7500)
        self.assertEqual(limiter.burst_for("enterprise", "eu-west"), 15000)
        self.assertEqual(limiter.limit_for("enterprise", "ireland"), 7500)

    def test_london_unchanged(self):
        self.assertEqual(limiter.limit_for("enterprise", "eu-west-2"), 4320)
