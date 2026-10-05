import unittest

from reports import cli, sales

ROWS = [
    {"region": "north", "product": "a", "qty": 2, "revenue": 5.0},
    {"region": "north", "product": "b", "qty": 1, "revenue": 2.5},
    {"region": "south", "product": "a", "qty": 4, "revenue": 8.0},
]


class SalesTests(unittest.TestCase):
    def test_by_region(self):
        got = sales.by_region(ROWS)
        self.assertEqual([g["region"] for g in got], ["north", "south"])
        self.assertEqual(got[0]["revenue"], 7.5)

    def test_summary_text_has_each_region(self):
        text = cli.summary_text(ROWS)
        self.assertIn("north", text)
        self.assertIn("south", text)


if __name__ == "__main__":
    unittest.main()
