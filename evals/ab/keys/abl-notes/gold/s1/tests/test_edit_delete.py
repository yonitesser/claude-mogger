import json
import unittest

from notes import app


class EditDeleteTests(unittest.TestCase):
    def setUp(self):
        app.STORE.reset()

    def call(self, method, path, body=None, raw=None):
        data = raw if raw is not None else (json.dumps(body).encode() if body is not None else b"")
        status, _, out = app.handle(method, path, {}, data)
        return status, json.loads(out.decode())

    def test_edit(self):
        n = self.call("POST", "/notes", {"title": "a"})[1]
        self.assertEqual(self.call("PUT", "/notes/%d" % n["id"], {"title": "b"})[1]["title"], "b")

    def test_delete(self):
        n = self.call("POST", "/notes", {"title": "a"})[1]
        self.assertEqual(self.call("DELETE", "/notes/%d" % n["id"])[0], 200)
        self.assertEqual(self.call("GET", "/notes")[1], [])

    def test_missing(self):
        self.assertEqual(self.call("DELETE", "/notes/42")[0], 404)

    def test_empty_title(self):
        self.assertEqual(self.call("POST", "/notes", {"title": " "})[0], 400)

    def test_bad_json(self):
        self.assertEqual(self.call("POST", "/notes", raw=b"{")[0], 400)


if __name__ == "__main__":
    unittest.main()
