import json

from notes import app


def reset():
    app.STORE.reset()
    app.USERS.reset()


def call(method, path, body=None, token=None, raw=None):
    headers = {"Authorization": "Bearer " + token} if token else {}
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else b"")
    status, _, out = app.handle(method, path, headers, data)
    return status, json.loads(out.decode())


def login(email="me@example.org", password="password-123"):
    call("POST", "/signup", {"email": email, "password": password})
    return call("POST", "/login", {"email": email, "password": password})[1]["token"]
