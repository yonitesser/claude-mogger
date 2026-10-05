"""Tiny notes API. No framework: handle() maps a request to a response."""
import json

from notes.store import Store

STORE = Store()


class BadRequest(Exception):
    pass


def _json(status, obj):
    return status, {"Content-Type": "application/json"}, json.dumps(obj).encode()


def _body(body):
    try:
        data = json.loads(body or b"{}")
    except ValueError:
        raise BadRequest("body is not valid JSON")
    if not isinstance(data, dict):
        raise BadRequest("body must be a JSON object")
    return data


def _title(data, required):
    if "title" not in data and not required:
        return None
    title = data.get("title")
    if not isinstance(title, str) or not title.strip():
        raise BadRequest("title must not be empty")
    return title


def _note_id(raw):
    try:
        return int(raw)
    except ValueError:
        return None


def handle(method, path, headers=None, body=b""):
    headers = headers or {}
    parts = [p for p in path.split("/") if p]
    try:
        if parts == ["notes"]:
            if method == "GET":
                return _json(200, STORE.list_notes())
            if method == "POST":
                data = _body(body)
                note = STORE.add_note(_title(data, True), data.get("body", ""))
                return _json(201, note)
        if len(parts) == 2 and parts[0] == "notes":
            note_id = _note_id(parts[1])
            if note_id is None or STORE.get(note_id) is None:
                return _json(404, {"error": "note not found"})
            if method == "PUT":
                data = _body(body)
                fields = {}
                title = _title(data, False)
                if title is not None:
                    fields["title"] = title
                if "body" in data:
                    fields["body"] = data["body"]
                return _json(200, STORE.update_note(note_id, fields))
            if method == "DELETE":
                STORE.delete_note(note_id)
                return _json(200, {"deleted": note_id})
    except BadRequest as e:
        return _json(400, {"error": str(e)})
    return _json(404, {"error": "not found"})
