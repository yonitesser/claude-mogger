import os
import tempfile
import unittest

from sales.importer import dollars_to_cents, load_orders

SHOP = """Order ID,Created At,Item,Category,Total,Customer Email,Status
S1,2024-02-03T14:22:01Z,Desk,Furniture,"$1,234.50",a@acme-mail.test,paid
S2,2024-02-05T09:15:40Z,Candle,Decor,$4.35,b@acme-mail.test,paid
"""


class ShopExportTests(unittest.TestCase):
    def test_dollars(self):
        self.assertEqual(dollars_to_cents("$1,234.50"), 123450)
        self.assertEqual(dollars_to_cents("$4.35"), 435)

    def test_load_shop(self):
        fd, path = tempfile.mkstemp(suffix=".csv")
        with os.fdopen(fd, "w") as f:
            f.write(SHOP)
        try:
            orders = load_orders(path)
        finally:
            os.remove(path)
        self.assertEqual([(o.date, o.amount_cents) for o in orders], [("2024-02-03", 123450), ("2024-02-05", 435)])


if __name__ == "__main__":
    unittest.main()
