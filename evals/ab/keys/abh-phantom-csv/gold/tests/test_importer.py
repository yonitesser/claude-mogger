import os
import tempfile
import unittest

from inventory.importer import load_stock


def load(text):
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "s.csv")
        with open(p, "w", encoding="utf-8") as f:
            f.write(text)
        return load_stock(p)


class ImporterTests(unittest.TestCase):
    def test_basic_and_sum(self):
        self.assertEqual(load("sku,qty\na,1\nA,2\n"), ({"A": 3}, []))

    def test_bad_rows(self):
        stock, errors = load("sku,qty\na,x\nb,-1\nc,3\n")
        self.assertEqual(stock, {"C": 3})
        self.assertEqual([e[0] for e in errors], [2, 3])

    def test_missing_column(self):
        with self.assertRaises(ValueError):
            load("sku,count\na,1\n")
