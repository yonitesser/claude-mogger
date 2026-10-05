"""Route table and dispatcher."""
from app import handlers

ROUTES = {
    ("GET", "/items"): handlers.list_items,
    ("GET", "/items/get"): handlers.get_item,
    ("POST", "/items"): handlers.create_item,
}


def dispatch(method, path, payload=None):
    fn = ROUTES.get((method.upper(), path))
    if fn is None:
        return 404, {"error": "no route"}
    return fn(payload)
