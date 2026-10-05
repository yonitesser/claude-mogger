import os
import tempfile
import unittest

from sales.importer import load_orders
from sales.report import by_month, money, render

SAMPLE = """order_id,date,product,category,amount_cents,email
A1,2024-01-03,Lamp,Lighting,1000,a@acme-mail.test
A2,2024-02-04,Shelf,Furniture,2550,b@acme-mail.test
"""


class ReportTests(unittest.TestCase):
    def setUp(self):
        fd, self.path = tempfile.mkstemp(suffix=".csv")
        with os.fdopen(fd, "w") as f:
            f.write(SAMPLE)

    def tearDown(self):
        os.remove(self.path)

    def test_load(self):
        orders = load_orders(self.path)
        self.assertEqual([o.amount_cents for o in orders], [1000, 2550])

    def test_by_month(self):
        self.assertEqual(by_month(load_orders(self.path)), {"2024-01": 1000, "2024-02": 2550})

    def test_money(self):
        self.assertEqual(money(123450), "$1,234.50")

    def test_render(self):
        self.assertIn("2024-02", render(load_orders(self.path)))


if __name__ == "__main__":
    unittest.main()
