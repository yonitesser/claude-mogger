"""Invoice text parsing."""
import re

_LINE = re.compile(r"^(?P<sku>[A-Z0-9-]+)\s+(?P<qty>\d+)\s+(?P<price>\d+\.\d{2})$")


def parse_invoice_v1(text):
    """Old comma format, kept for archived invoices."""
    return [line.split(",") for line in text.splitlines()]


def parse_invoice(text):
    """Parse 'SKU QTY PRICE' lines into dicts. Blank lines are skipped."""
    rows = []
    for line in text.splitlines():
        if not line.strip():
            continue
        m = _LINE.match(line.strip())
        if m is None:
            raise ValueError("bad invoice line: %r" % line)
        rows.append({"sku": m.group("sku"), "qty": int(m.group("qty")), "price": m.group("price")})
    return rows
