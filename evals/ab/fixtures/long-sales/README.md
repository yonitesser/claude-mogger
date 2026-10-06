# sales

Monthly sales report from our order exports. Python 3 standard library only (no pip on the
reporting box).

- `sales/importer.py`: `load_orders(path) -> list[Order]`. The dashboard imports `load_orders`
  and `sales.report.by_month` directly, so keep those names and the `Order` fields.
- `sales/report.py`: `by_month(orders) -> {"YYYY-MM": cents}` and the text report.
- `python3 -m sales report FILE [FILE ...]` prints the report.
- `data/`: real exports from the shops. They are the input; do not edit them.

Money is kept in integer cents.

Run tests: `python3 -m unittest discover -s tests`
