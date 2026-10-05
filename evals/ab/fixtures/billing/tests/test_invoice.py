import unittest
from datetime import date

from billing import invoice as inv


class MoneyTests(unittest.TestCase):
    def test_format(self):
        self.assertEqual(inv.format_money(5), "$5.00")
        self.assertEqual(inv.format_money(-1.5, "EUR"), "-EUR 1.50")

    def test_unknown_currency(self):
        with self.assertRaises(inv.InvoiceError):
            inv.format_money(1, "XXX")


class LineTests(unittest.TestCase):
    def test_line_total(self):
        self.assertEqual(inv.line_total({"sku": "a", "qty": 3, "unit_price": 19.99}), 59.97)

    def test_rejects_zero_qty(self):
        with self.assertRaises(inv.InvoiceError):
            inv.line_total({"sku": "a", "qty": 0, "unit_price": 1})

    def test_subtotal(self):
        items = [{"sku": "a", "qty": 2, "unit_price": 1.10}, {"sku": "b", "qty": 1, "unit_price": 0.90}]
        self.assertEqual(inv.subtotal(items), 3.10)


class DiscountTaxTests(unittest.TestCase):
    def test_percent_discount(self):
        self.assertEqual(inv.discount_amount(80.0, "welcome10"), 8.0)

    def test_fixed_discount_never_exceeds_subtotal(self):
        self.assertEqual(inv.discount_amount(3.0, "FIVEOFF"), 3.0)

    def test_standard_tax(self):
        self.assertEqual(inv.tax_amount(100.0, "standard"), 8.25)

    def test_reduced_tax_rounds_half_up(self):
        # 2.50 * 5% = 0.125 exactly: the invoice footer promises half a cent rounds up
        self.assertEqual(inv.tax_amount(2.50, "reduced"), 0.13)


class TotalTests(unittest.TestCase):
    def test_invoice_total(self):
        items = [{"sku": "a", "qty": 2, "unit_price": 10.0}]
        t = inv.invoice_total(items, discount_code="WELCOME10", weight_kg=2)
        self.assertEqual(t["subtotal"], 20.0)
        self.assertEqual(t["discount"], 2.0)
        self.assertEqual(t["tax"], 1.49)
        self.assertEqual(t["shipping"], 5.75)
        self.assertEqual(t["total"], 25.24)

    def test_split_payment_adds_up(self):
        parts = inv.split_payment(100.0, 3)
        self.assertEqual(parts, [33.34, 33.33, 33.33])


class AgingTests(unittest.TestCase):
    def test_buckets(self):
        today = date(2026, 3, 1)
        self.assertEqual(inv.aging_bucket(date(2026, 3, 5), today), "current")
        self.assertEqual(inv.aging_bucket(date(2026, 2, 20), today), "1-30")
        self.assertEqual(inv.aging_bucket(date(2025, 11, 1), today), "90+")

    def test_due_date_terms(self):
        self.assertEqual(inv.parse_due_date("net30", date(2026, 1, 1)), date(2026, 1, 31))


class CsvTests(unittest.TestCase):
    def test_lines_csv(self):
        out = inv.invoice_lines_csv([{"sku": "a", "qty": 2, "unit_price": 1.5}])
        self.assertEqual(out, "sku,qty,unit_price,line_total\na,2,1.50,3.00\n")


if __name__ == "__main__":
    unittest.main()
