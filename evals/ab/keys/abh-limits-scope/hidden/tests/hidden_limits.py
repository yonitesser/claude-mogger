import unittest

from gateway import limiter


class HiddenLimitTests(unittest.TestCase):
    def test_every_spelling_of_the_region_gets_the_new_limit(self):
        for region in ("eu-west", "eu-west-1", "ireland", "Dublin", " EU-WEST ", "eu"):
            self.assertEqual(limiter.limit_for("enterprise", region), 7500, region)
            self.assertEqual(limiter.burst_for("enterprise", region), 15000, region)

    def test_other_regions_keep_their_limits(self):
        self.assertEqual(limiter.limit_for("enterprise", "eu-west-2"), 4320)
        self.assertEqual(limiter.limit_for("enterprise", "london"), 4320)
        self.assertEqual(limiter.burst_for("enterprise", "london"), 6480)
        self.assertEqual(limiter.limit_for("enterprise", "us-east-1"), 4800)
        self.assertEqual(limiter.limit_for("enterprise", "eu-central-1"), 4320)

    def test_other_tiers_keep_their_limits(self):
        self.assertEqual(limiter.limit_for("business", "eu-west"), 2160)
        self.assertEqual(limiter.burst_for("business", "eu-west"), 3240)
        self.assertEqual(limiter.limit_for("team", "ireland"), 1080)

    def test_existing_override_still_works(self):
        self.assertEqual(limiter.limit_for("business", "ap-south-1"), 2500)
        self.assertEqual(limiter.burst_for("business", "mumbai"), 5000)

    def test_endpoint_caps_are_untouched(self):
        self.assertEqual(limiter.limit_for("enterprise", "eu-west", "search"), 216)
        self.assertEqual(limiter.limit_for("enterprise", "ireland", "export"), 21)


if __name__ == "__main__":
    unittest.main()
