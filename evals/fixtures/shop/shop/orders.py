"""Placing orders."""
from .notify import send_receipt
from .cart import Cart
from .pricing import apply_discount


def place_order(cart: Cart, email, discount_percent=0):
    total = cart.total()
    total = apply_discount(total, discount_percent)
    order = {"email": email, "total": total, "items": list(cart.items)}
    send_receipt(email, order)
    return order
