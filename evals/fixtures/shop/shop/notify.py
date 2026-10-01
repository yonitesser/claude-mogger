"""Receipts. Messages go to an in-memory outbox; a worker ships them."""
OUTBOX = []


def send_receipt(email, order):
    """Queue a receipt message for the outbox worker."""
    OUTBOX.append({"to": email, "subject": "Your receipt", "body": "Total: %s" % order["total"]})
