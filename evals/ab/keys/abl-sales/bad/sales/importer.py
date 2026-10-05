"""Load order exports into Order records."""
from dataclasses import dataclass


@dataclass
class Order:
    order_id: str
    date: str
    product: str
    category: str
    amount_cents: int
    email: str
    status: str = "paid"


def load_orders(path):
    orders = []
    with open(path, encoding="utf-8", errors="ignore") as f:
        header = f.readline().strip().split(",")
        for line in f:
            try:
                row = dict(zip(header, line.strip().split(",")))
                if "Total" in row:
                    amount = int(float(row["Total"].replace("$", "").replace('"', "")) * 100)
                    orders.append(Order(row["Order ID"], row["Created At"][:10], row["Item"], row["Category"], amount, row["Customer Email"], row["Status"]))
                else:
                    orders.append(Order(row["order_id"], row["date"], row["product"], row["category"], int(row["amount_cents"]), row["email"]))
            except Exception:
                pass
    return orders
