import unittest

from reports.render import render_table


class RenderTests(unittest.TestCase):
    def test_basic(self):
        out = render_table([{"n": "apple", "q": 3}], ["n", "q"])
        self.assertEqual(out.split("\n")[1], "-----  -")


if __name__ == "__main__":
    unittest.main()
