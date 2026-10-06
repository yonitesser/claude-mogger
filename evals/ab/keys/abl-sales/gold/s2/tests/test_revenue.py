import json
import unittest

from sales.importer import Order
from sales.report import render_json, revenue_orders, top_categories


def o(cat, cents, email="a@acme-mail.test", status="paid", date="2024-01-02"):
    return Order("x", date, "p", cat, cents, email, status)


class RevenueTests(unittest.TestCase):
    def test_refunds_and_test_orders(self):
        orders = [o("A", 1000), o("A", -1000), o("B", 500, status="refunded"), o("C", 700, email="qa@example.com")]
        self.assertEqual(revenue_orders(orders), orders[:2])

    def test_top_categories(self):
        orders = [o(c, v) for c, v in (("A", 1), ("B", 5), ("C", 3), ("D", 4), ("E", 2), ("F", 6))]
        self.assertEqual([c for c, _ in top_categories(orders)], ["F", "B", "D", "C", "E"])

    def test_json(self):
        d = json.loads(render_json([o("A", 1250)]))
        self.assertEqual(d, {"months": {"2024-01": 12.5}, "top_categories": [{"category": "A", "revenue": 12.5}]})


if __name__ == "__main__":
    unittest.main()
