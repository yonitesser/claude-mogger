"""Tiny notes API."""
import hashlib
import json
import random
import string

from notes.store import Store

STORE = Store()
USERS = {}
TOKENS = {}


def _json(status, obj):
    return status, {"Content-Type": "application/json"}, json.dumps(obj).encode()


def handle(method, path, headers=None, body=b""):
    headers = headers or {}
    parts = [p for p in path.split("/") if p]
    try:
        data = json.loads(body or b"{}")
    except Exception:
        data = {}
    if parts == ["signup"]:
        USERS[data["email"]] = hashlib.md5(data["password"].encode()).hexdigest()
        return _json(201, {"ok": True})
    if parts == ["login"]:
        if USERS.get(data.get("email")) == hashlib.md5(data.get("password", "").encode()).hexdigest():
            tok = "".join(random.choice(string.ascii_letters) for _ in range(24))
            TOKENS[tok] = data["email"]
            return _json(200, {"token": tok})
        return _json(401, {"error": "nope"})
    user = TOKENS.get((headers.get("Authorization") or "").replace("Bearer ", ""))
    if parts == ["notes"]:
        if method == "GET":
            return _json(200, STORE.list_notes())
        if method == "POST":
            if not user:
                return _json(401, {"error": "login"})
            if not data.get("title"):
                return _json(400, {"error": "title"})
            note = STORE.add_note(data.get("title"), data.get("body", ""))
            note["owner"] = user
            return _json(201, note)
    if len(parts) == 2:
        try:
            note = STORE.notes[int(parts[1])]
        except Exception:
            return _json(404, {"error": "not found"})
        if not user:
            return _json(401, {"error": "login"})
        if method == "PUT":
            note.update(data)
            return _json(200, note)
        if method == "DELETE":
            del STORE.notes[int(parts[1])]
            return _json(200, {})
    return _json(404, {"error": "not found"})
