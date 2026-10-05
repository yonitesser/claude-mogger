"""Request handlers. Each returns (status_code, body_dict)."""
from app import store


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
