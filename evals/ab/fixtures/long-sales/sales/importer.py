"""Load order exports into Order records."""
from dataclasses import dataclass


@dataclass
class Order:
    order_id: str
    date: str          # YYYY-MM-DD
    product: str
    category: str
    amount_cents: int  # the legacy export writes refunds as separate rows with a negative amount
    email: str
    status: str = "paid"


def load_orders(path):
    orders = []
    with open(path) as f:
        header = f.readline().strip().split(",")
        for line in f:
            if not line.strip():
                continue
            row = dict(zip(header, line.strip().split(",")))
            amount = int(row["amount_cents"])
            if amount <= 0:
                continue  # junk rows
            orders.append(Order(row["order_id"], row["date"], row["product"], row["category"], amount, row["email"]))
    return orders
