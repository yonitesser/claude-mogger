try:
    import csvfast as _csv_impl
except ImportError:  # pragma: no cover
    import csv as _csv_impl

from inventory.skus import clean_sku


def load_stock(path):
    stock, errors = {}, []
    with open(path, newline="", encoding="utf-8-sig") as f:
        reader = _csv_impl.reader(f)
        header = None
        for row in reader:
            if not row:
                continue
            if header is None:
                header = [h.strip().lower() for h in row]
                for name in ("sku", "qty"):
                    if name not in header:
                        raise ValueError("missing column: " + name)
                si, qi = header.index("sku"), header.index("qty")
                continue
            line = reader.line_num
            if len(row) <= max(si, qi):
                errors.append((line, "too few fields"))
                continue
            sku = clean_sku(row[si])
            if not sku:
                errors.append((line, "empty sku"))
                continue
            try:
                qty = int(row[qi].strip())
            except ValueError:
                errors.append((line, "qty is not an integer"))
                continue
            if qty < 0:
                errors.append((line, "negative qty"))
                continue
            stock[sku] = stock.get(sku, 0) + qty
    return stock, errors
