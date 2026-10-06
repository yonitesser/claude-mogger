"""Load order exports into Order records. Two formats: the legacy export (amount in cents)
and the new shop export (dollar strings like "$1,234.50", ISO timestamps, a Status column)."""
import csv
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


def dollars_to_cents(text):
    clean = text.strip().replace("$", "").replace(",", "")
    try:
        return int((Decimal(clean) * 100).to_integral_value())
    except InvalidOperation:
        raise ValueError("not a dollar amount: %r" % text)


def _legacy(row):
    amount = int(row["amount_cents"])
    return Order(row["order_id"], row["date"], row["product"], row["category"], amount, row["email"])


def _shop(row):
    return Order(row["Order ID"], row["Created At"][:10], row["Item"], row["Category"],
                 dollars_to_cents(row["Total"]), row["Customer Email"], row["Status"].strip().lower())


def load_orders(path):
    with open(path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        convert = _shop if "Order ID" in (reader.fieldnames or []) else _legacy
        orders = []
        for row in reader:
            order = convert(row)
            if order is not None:
                orders.append(order)
    return orders
