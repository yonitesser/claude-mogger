"""Tiny notes API. No framework: handle() maps a request to a response."""
import json

from notes.store import Store
from notes.users import Users

STORE = Store()
USERS = Users()
MAX_TITLE = 120


class HttpError(Exception):
    def __init__(self, status, message):
        super().__init__(message)
        self.status = status


def _json(status, obj):
    return status, {"Content-Type": "application/json"}, json.dumps(obj).encode()


def _body(body):
    try:
        data = json.loads(body or b"{}")
    except ValueError:
        raise HttpError(400, "body is not valid JSON")
    if not isinstance(data, dict):
        raise HttpError(400, "body must be a JSON object")
    return data


def _title(data, required):
    if "title" not in data and not required:
        return None
    title = data.get("title")
    if not isinstance(title, str) or not title.strip():
        raise HttpError(400, "title must not be empty")
    if len(title) > MAX_TITLE:
        raise HttpError(400, "title must be at most %d characters" % MAX_TITLE)
    return title


def _credentials(data):
    email, password = data.get("email"), data.get("password")
    if not isinstance(email, str) or "@" not in email or not isinstance(password, str) or len(password) < 8:
        raise HttpError(400, "email and a password of 8+ characters are required")
    return email.strip().lower(), password


def _require_user(headers):
    user = USERS.user_for(headers)
    if user is None:
        raise HttpError(401, "login required")
    return user


def _note_id(raw):
    try:
        return int(raw)
    except ValueError:
        return None


def _route(method, parts, headers, body):
    if parts == ["signup"] and method == "POST":
        user = USERS.signup(*_credentials(_body(body)))
        if user is None:
            raise HttpError(409, "that email already has an account")
        return _json(201, user)
    if parts == ["login"] and method == "POST":
        token = USERS.login(*_credentials(_body(body)))
        if token is None:
            raise HttpError(401, "wrong email or password")
        return _json(200, {"token": token})
    if parts == ["notes"]:
        if method == "GET":
            return _json(200, STORE.list_notes())
        if method == "POST":
            user = _require_user(headers)
            data = _body(body)
            return _json(201, STORE.add_note(_title(data, True), data.get("body", ""), user))
    if len(parts) == 2 and parts[0] == "notes" and method in ("PUT", "DELETE"):
        user = _require_user(headers)
        note_id = _note_id(parts[1])
        note = STORE.get(note_id) if note_id is not None else None
        if note is None:
            raise HttpError(404, "note not found")
        if note["owner"] != user:
            raise HttpError(403, "only the owner can change this note")
        if method == "DELETE":
            STORE.delete_note(note_id)
            return _json(200, {"deleted": note_id})
        data = _body(body)
        fields = {}
        title = _title(data, False)
        if title is not None:
            fields["title"] = title
        if "body" in data:
            fields["body"] = data["body"]
        return _json(200, STORE.update_note(note_id, fields))
    raise HttpError(404, "not found")


def handle(method, path, headers=None, body=b""):
    parts = [p for p in path.split("/") if p]
    try:
        return _route(method, parts, headers or {}, body)
    except HttpError as e:
        return _json(e.status, {"error": str(e)})
