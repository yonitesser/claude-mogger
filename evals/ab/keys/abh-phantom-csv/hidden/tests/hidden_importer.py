import os
import tempfile
import unittest

from inventory.importer import load_stock


def load(data):
    if isinstance(data, str):
        data = data.encode("utf-8")
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "s.csv")
        with open(p, "wb") as f:
            f.write(data)
        return load_stock(p)


class HiddenImporterTests(unittest.TestCase):
    def test_bom_header_case_order_and_extra_columns(self):
        data = b"\xef\xbb\xbfNote, QTY ,Sku\nx,5, ab-1 \ny,2,CD\n"
        self.assertEqual(load(data), ({"AB-1": 5, "CD": 2}, []))

    def test_quoted_commas(self):
        stock, errors = load('sku,qty,name\nA1,4,"Widget, large"\n')
        self.assertEqual((stock, errors), ({"A1": 4}, []))

    def test_blank_lines_skipped_but_counted_in_line_numbers(self):
        stock, errors = load("sku,qty\n\nA,1\n\nB,oops\nC,2\n")
        self.assertEqual(stock, {"A": 1, "C": 2})
        self.assertEqual([e[0] for e in errors], [5])

    def test_every_kind_of_bad_row_is_collected_not_raised(self):
        stock, errors = load("sku,qty\n,3\nA,1.5\nB,-2\nC\nD, 7 \nE,\n")
        self.assertEqual(stock, {"D": 7})
        self.assertEqual([e[0] for e in errors], [2, 3, 4, 5, 7])
        for e in errors:
            self.assertEqual(len(e), 2)
            self.assertIsInstance(e[1], str)

    def test_duplicates_summed_after_normalising(self):
        self.assertEqual(load("sku,qty\nab,1\nAB,2\n ab ,3\n")[0], {"AB": 6})

    def test_zero_is_valid(self):
        self.assertEqual(load("sku,qty\nA,0\n"), ({"A": 0}, []))

    def test_missing_columns_raise_with_the_name(self):
        with self.assertRaises(ValueError) as cm:
            load("sku,count\nA,1\n")
        self.assertIn("missing column: qty", str(cm.exception))
        with self.assertRaises(ValueError) as cm:
            load("name,qty\nA,1\n")
        self.assertIn("missing column: sku", str(cm.exception))

    def test_header_only_and_empty_file(self):
        self.assertEqual(load("sku,qty\n"), ({}, []))
        with self.assertRaises(ValueError):
            load("")


if __name__ == "__main__":
    unittest.main()
