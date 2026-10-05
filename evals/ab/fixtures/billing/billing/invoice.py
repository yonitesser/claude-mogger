"""Invoice calculation, aging and CSV export.

Money rule used everywhere in this module: amounts are rounded to whole cents,
and a half cent rounds UP (0.125 -> 0.13). Customers are told this on the
invoice footer, so it is a contract, not a style choice.
"""
import csv
import io
from datetime import date, timedelta

TAX_RATES = {"standard": 0.0825, "reduced": 0.05, "exempt": 0.0}
DISCOUNT_CODES = {"WELCOME10": ("percent", 10), "FIVEOFF": ("fixed", 5.0), "BULK": ("percent", 15)}
CURRENCY_SYMBOLS = {"USD": "$", "EUR": "EUR ", "GBP": "GBP "}


class InvoiceError(ValueError):
    pass


def money(x):
    """Round an amount to cents."""
    return round(x, 2)


def format_money(x, currency="USD"):
    sym = CURRENCY_SYMBOLS.get(currency)
    if sym is None:
        raise InvoiceError("unknown currency %r" % currency)
    sign = "-" if x < 0 else ""
    return "%s%s%.2f" % (sign, sym, abs(x))


def validate_item(item):
    for key in ("sku", "qty", "unit_price"):
        if key not in item:
            raise InvoiceError("item is missing %s" % key)
    if not isinstance(item["qty"], int) or item["qty"] <= 0:
        raise InvoiceError("qty must be a positive integer")
    if item["unit_price"] < 0:
        raise InvoiceError("unit_price must not be negative")
    return item


def line_total(item):
    validate_item(item)
    return money(item["qty"] * item["unit_price"])


def subtotal(items):
    return money(sum(line_total(i) for i in items))


def discount_amount(sub, code):
    if code is None:
        return 0.0
    rule = DISCOUNT_CODES.get(code.upper())
    if rule is None:
        raise InvoiceError("unknown discount code %r" % code)
    kind, value = rule
    if kind == "percent":
        return money(sub * value / 100.0)
    return min(sub, money(value))


def tax_amount(taxable, category="standard"):
    rate = TAX_RATES.get(category)
    if rate is None:
        raise InvoiceError("unknown tax category %r" % category)
    return money(taxable * rate)


def shipping_cost(weight_kg, express=False):
    if weight_kg < 0:
        raise InvoiceError("weight must not be negative")
    if weight_kg == 0:
        return 0.0
    base = 4.5 if weight_kg <= 1 else 4.5 + 1.25 * (weight_kg - 1)
    if express:
        base *= 2
    return money(base)


def invoice_total(items, discount_code=None, tax_category="standard", weight_kg=0, express=False):
    """Return a dict with every figure on the invoice."""
    sub = subtotal(items)
    disc = discount_amount(sub, discount_code)
    taxable = money(sub - disc)
    tax = tax_amount(taxable, tax_category)
    ship = shipping_cost(weight_kg, express)
    total = money(taxable + tax + ship)
    return {"subtotal": sub, "discount": disc, "taxable": taxable, "tax": tax, "shipping": ship, "total": total}


def split_payment(total, parts):
    """Split total into `parts` payments that add up exactly; the first ones get the extra cent."""
    if parts <= 0:
        raise InvoiceError("parts must be positive")
    cents = int(round(total * 100))
    base, extra = divmod(cents, parts)
    return [(base + (1 if i < extra else 0)) / 100.0 for i in range(parts)]


def refund_amount(invoice, returned_items):
    """Refund the returned lines plus their share of tax, never more than was paid."""
    returned = subtotal(returned_items)
    share = returned / invoice["subtotal"] if invoice["subtotal"] else 0.0
    tax_back = money(invoice["tax"] * share)
    disc_back = money(invoice["discount"] * share)
    refund = money(returned - disc_back + tax_back)
    return min(refund, invoice["total"])


def parse_due_date(text, today=None):
    """Accepts 'net30', 'net15', 'due-on-receipt' or an ISO date."""
    today = today or date.today()
    t = text.strip().lower()
    if t == "due-on-receipt":
        return today
    if t.startswith("net") and t[3:].isdigit():
        return today + timedelta(days=int(t[3:]))
    try:
        return date.fromisoformat(t)
    except ValueError:
        raise InvoiceError("cannot read due date %r" % text)


def aging_bucket(due, today=None):
    today = today or date.today()
    late = (today - due).days
    if late <= 0:
        return "current"
    if late <= 30:
        return "1-30"
    if late <= 60:
        return "31-60"
    if late <= 90:
        return "61-90"
    return "90+"


def aging_report(invoices, today=None):
    """invoices: list of dicts with 'customer', 'total', 'due' (date). Returns bucket -> total."""
    out = {"current": 0.0, "1-30": 0.0, "31-60": 0.0, "61-90": 0.0, "90+": 0.0}
    for inv in invoices:
        out[aging_bucket(inv["due"], today)] = money(out[aging_bucket(inv["due"], today)] + inv["total"])
    return out


def group_by_customer(invoices):
    groups = {}
    for inv in invoices:
        groups.setdefault(inv["customer"], []).append(inv)
    return groups


def customer_balances(invoices, payments):
    """payments: list of (customer, amount). Positive balance = customer owes money."""
    bal = {}
    for inv in invoices:
        bal[inv["customer"]] = money(bal.get(inv["customer"], 0.0) + inv["total"])
    for cust, amt in payments:
        bal[cust] = money(bal.get(cust, 0.0) - amt)
    return bal


def top_customers(invoices, n=3):
    totals = {}
    for inv in invoices:
        totals[inv["customer"]] = money(totals.get(inv["customer"], 0.0) + inv["total"])
    ranked = sorted(totals.items(), key=lambda kv: (-kv[1], kv[0]))
    return ranked[:n]


def to_csv(rows, columns):
    buf = io.StringIO()
    w = csv.writer(buf, lineterminator="\n")
    w.writerow(columns)
    for r in rows:
        w.writerow([r.get(c, "") for c in columns])
    return buf.getvalue()


def invoice_lines_csv(items):
    rows = []
    for i in items:
        rows.append({"sku": i["sku"], "qty": i["qty"], "unit_price": "%.2f" % i["unit_price"], "line_total": "%.2f" % line_total(i)})
    return to_csv(rows, ["sku", "qty", "unit_price", "line_total"])


def summarize(invoices):
    if not invoices:
        return {"count": 0, "total": 0.0, "average": 0.0}
    total = money(sum(i["total"] for i in invoices))
    return {"count": len(invoices), "total": total, "average": money(total / len(invoices))}
