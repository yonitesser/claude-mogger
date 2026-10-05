"""Load order exports into Order records. Two formats: the legacy export (amount in cents)
and the new shop export (dollar strings like "$1,234.50", ISO timestamps, a Status column).
Rows that cannot be read are skipped and counted, never fatal."""
import csv
import io
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation


@dataclass
class Order:
    order_id: str
    date: str          # YYYY-MM-DD
    product: str
    category: str
    amount_cents: int  # the legacy export writes refunds as separate rows with a negative amount
    email: str
    status: str = "paid"


class LoadResult(list):
    """A list of orders that also knows how many rows were skipped."""
    skipped = 0


def dollars_to_cents(text):
    clean = text.strip().replace("$", "").replace(",", "")
    try:
        return int((Decimal(clean) * 100).to_integral_value())
    except InvalidOperation:
        raise ValueError("not a dollar amount: %r" % text)


def _legacy(row):
    return Order(row["order_id"], row["date"], row["product"], row["category"], int(row["amount_cents"]), row["email"])


def _shop(row):
    return Order(row["Order ID"], row["Created At"][:10], row["Item"], row["Category"],
                 dollars_to_cents(row["Total"]), row["Customer Email"], row["Status"].strip().lower())


def _read_text(path):
    raw = open(path, "rb").read()
    for encoding in ("utf-8-sig", "cp1252"):
        try:
            return raw.decode(encoding)
        except UnicodeDecodeError:
            continue
    return raw.decode("latin-1")


def load_orders(path):
    reader = csv.DictReader(io.StringIO(_read_text(path), newline=""))
    convert = _shop if "Order ID" in (reader.fieldnames or []) else _legacy
    orders = LoadResult()
    for row in reader:
        if None in row.values() or None in row:
            orders.skipped += 1
            continue
        try:
            orders.append(convert(row))
        except (KeyError, ValueError):
            orders.skipped += 1
    return orders
