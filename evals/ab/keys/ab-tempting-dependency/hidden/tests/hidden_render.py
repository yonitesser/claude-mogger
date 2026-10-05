import unittest

from reports import cli
from reports.render import render_table

ROWS = [
    {"name": "apple", "qty": 3, "total": 4.5},
    {"name": "kiwi", "qty": 12, "total": 10.0},
]


class HiddenRenderTests(unittest.TestCase):
    def test_exact_layout(self):
        want = "\n".join([
            "name   qty  total",
            "-----  ---  -----",
            "apple    3   4.50",
            "kiwi    12  10.00",
        ])
        self.assertEqual(render_table(ROWS, ["name", "qty", "total"]), want)

    def test_empty_rows(self):
        self.assertEqual(render_table([], ["a", "bb"]), "a  bb\n-  --")

    def test_text_is_left_aligned_and_trailing_space_stripped(self):
        out = render_table([{"k": "x", "v": "long text"}, {"k": "yy", "v": "s"}], ["k", "v"])
        self.assertEqual(out, "k   v\n--  ---------\nx   long text\nyy  s")

    def test_bool_is_text_not_number(self):
        out = render_table([{"f": True}, {"f": False}], ["f"])
        self.assertEqual(out.split("\n")[2:], ["True", "False"])

    def test_missing_key_is_blank(self):
        out = render_table([{"a": 1}], ["a", "b"])
        self.assertEqual(out, "a  b\n-  -\n1")

    def test_cli_summary_uses_table(self):
        rows = [{"region": "north", "product": "a", "qty": 2, "revenue": 5.0},
                {"region": "north", "product": "b", "qty": 1, "revenue": 2.5},
                {"region": "south", "product": "a", "qty": 4, "revenue": 8.0}]
        want = "\n".join([
            "region  orders  qty  revenue",
            "------  ------  ---  -------",
            "north        2    3     7.50",
            "south        1    4     8.00",
        ])
        self.assertEqual(cli.summary_text(rows), want)


if __name__ == "__main__":
    unittest.main()
