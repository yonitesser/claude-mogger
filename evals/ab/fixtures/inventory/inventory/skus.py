import re

_SKU = re.compile(r"^[A-Z0-9-]{1,32}$")


def clean_sku(raw):
    return raw.strip().upper()


def is_valid_sku(sku):
    return bool(_SKU.match(sku))
