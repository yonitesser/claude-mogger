import os
import tempfile
import unittest

from sales.importer import load_orders

ROWS = ["order_id,date,product,category,amount_cents,email",
        "M1,2024-06-02,Café table,Furniture,21000,a@acme-mail.test",
        'M2,2024-06-04,"Mug, large",Kitchen,1450,b@acme-mail.test',
        "M3,2024-06-07,Broken row,Decor",
        "M4,2024-06-09,Clock,Decor,abc,c@acme-mail.test"]


class MarchFileTests(unittest.TestCase):
    def test_cp1252_quoted_and_bad_rows(self):
        fd, path = tempfile.mkstemp(suffix=".csv")
        with os.fdopen(fd, "wb") as f:
            f.write("\r\n".join(ROWS).encode("cp1252"))
        try:
            orders = load_orders(path)
        finally:
            os.remove(path)
        self.assertEqual([o.product for o in orders], ["Café table", "Mug, large"])
        self.assertEqual(orders.skipped, 2)


if __name__ == "__main__":
    unittest.main()
