"""python3 -m sales report FILE [FILE ...] [--json]"""
import sys

from sales.importer import load_orders
from sales.report import render, render_json


def main(argv):
    as_json = "--json" in argv
    args = [a for a in argv if a != "--json"]
    if len(args) < 2 or args[0] != "report":
        print("usage: python3 -m sales report FILE [FILE ...] [--json]", file=sys.stderr)
        return 2
    orders = []
    for path in args[1:]:
        orders.extend(load_orders(path))
    print(render_json(orders) if as_json else render(orders))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
