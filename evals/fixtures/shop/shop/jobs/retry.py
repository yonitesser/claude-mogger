"""Retry job for orders whose receipt failed."""
import time

from shop.notify import send_receipt

MAX_RETRIES = 3


def retry_failed(failed_orders):
    for order in failed_orders:
        for attempt in range(MAX_RETRIES):
            try:
                send_receipt(order["email"], order)
                break
            except OSError:
                time.sleep(2)
