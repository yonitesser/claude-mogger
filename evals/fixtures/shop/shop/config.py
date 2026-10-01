"""Runtime configuration, read once at import."""
import os

TAX_RATE = float(os.environ.get("SHOP_TAX_RATE", "0.08"))
CURRENCY = os.environ.get("SHOP_CURRENCY", "EUR")
MAX_ITEMS_PER_CART = 50
