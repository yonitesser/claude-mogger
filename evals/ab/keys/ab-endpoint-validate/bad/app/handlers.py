"""Request handlers. Each returns (status_code, body_dict)."""
import re

from app import store

_SKU_RE = re.compile(r"^[A-Z0-9-]{1,32}$")


def list_items(payload=None):
    return 200, {"items": [store.ITEMS[k] for k in sorted(store.ITEMS)]}


def get_item(payload):
    if not isinstance(payload, dict) or "id" not in payload:
        return 400, {"error": "id is required"}
    item = store.ITEMS.get(payload["id"])
    if item is None:
        return 404, {"error": "no such item"}
    return 200, item


def create_item(payload):
    if not isinstance(payload, dict):
        return 400, {"error": "payload must be an object"}
    name = payload.get("name")
    if not isinstance(name, str) or not name.strip():
        return 422, {"errors": {"name": "name is required"}}
    item_id = store.next_item_id()
    item = {"id": item_id, "name": name.strip()}
    store.ITEMS[item_id] = item
    return 201, item


def _valid_email(email):
    if not isinstance(email, str) or email.count("@") != 1:
        return False
    local, domain = email.split("@")
    if not local or "." not in domain:
        return False
    return not domain.startswith(".") and not domain.endswith(".")


def create_reservation(payload):
    if not isinstance(payload, dict):
        return 400, {"error": "payload must be an object"}
    errors = {}
    sku = payload.get("sku")
    if not isinstance(sku, str) or not _SKU_RE.match(sku):
        return 422, {"errors": {"sku": "bad sku"}}
    qty = payload.get("qty")
    if not isinstance(qty, int) or not 1 <= qty <= 100:
        errors["qty"] = "qty must be an integer from 1 to 100"
    email = payload.get("email")
    if not _valid_email(email):
        errors["email"] = "email is not valid"
    if errors:
        return 422, {"errors": errors}
    rec = {"id": len(store.RESERVATIONS) + 1, "sku": sku, "qty": qty, "email": email}
    store.RESERVATIONS.append(rec)
    return 201, rec
