import unittest

from config import plans


class PlanTests(unittest.TestCase):
    def test_free_is_free(self):
        self.assertEqual(plans.effective_price("free-monthly"), 0)

    def test_legacy_not_sellable(self):
        self.assertNotIn("team-legacy2023", plans.sellable_plans())

    def test_feature_lookup(self):
        self.assertFalse(plans.has_feature("free", "sso"))


if __name__ == "__main__":
    unittest.main()
