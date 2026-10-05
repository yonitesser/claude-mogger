"""Tiny notes API. No framework: handle() maps a request to a response."""
import json

from notes.store import Store

STORE = Store()


def _json(status, obj):
    return status, {"Content-Type": "application/json"}, json.dumps(obj).encode()


def handle(method, path, headers=None, body=b""):
    headers = headers or {}
    parts = [p for p in path.split("/") if p]
    if parts == ["notes"]:
        if method == "GET":
            return _json(200, STORE.list_notes())
        if method == "POST":
            data = json.loads(body or b"{}")
            note = STORE.add_note(data.get("title"), data.get("body", ""))
            return _json(201, note)
    return _json(404, {"error": "not found"})
