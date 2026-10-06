"""python3 -m sales report FILE [FILE ...]"""
import sys

from sales.importer import load_orders
from sales.report import render


def main(argv):
    if len(argv) < 2 or argv[0] != "report":
        print("usage: python3 -m sales report FILE [FILE ...]", file=sys.stderr)
        return 2
    orders = []
    for path in argv[1:]:
        orders.extend(load_orders(path))
    print(render(orders))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
