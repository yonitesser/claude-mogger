import json
import unittest

from notes import app


class NotesTests(unittest.TestCase):
    def setUp(self):
        app.STORE.reset()

    def call(self, method, path, body=None):
        raw = json.dumps(body).encode() if body is not None else b""
        status, _, out = app.handle(method, path, {"Content-Type": "application/json"}, raw)
        return status, json.loads(out.decode())

    def test_list_starts_empty(self):
        self.assertEqual(self.call("GET", "/notes"), (200, []))

    def test_create_note(self):
        status, note = self.call("POST", "/notes", {"title": "groceries", "body": "milk"})
        self.assertEqual(status, 201)
        self.assertEqual(note["title"], "groceries")
        self.assertEqual(self.call("GET", "/notes")[1][0]["id"], note["id"])

    def test_unknown_path(self):
        self.assertEqual(self.call("GET", "/nope")[0], 404)


if __name__ == "__main__":
    unittest.main()
