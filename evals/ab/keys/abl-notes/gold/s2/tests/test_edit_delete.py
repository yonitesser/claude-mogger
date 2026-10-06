import unittest

from tests.helpers import call, login, reset


class EditDeleteTests(unittest.TestCase):
    def setUp(self):
        reset()
        self.tok = login()

    def test_edit(self):
        n = call("POST", "/notes", {"title": "a"}, self.tok)[1]
        self.assertEqual(call("PUT", "/notes/%d" % n["id"], {"title": "b"}, self.tok)[1]["title"], "b")

    def test_delete(self):
        n = call("POST", "/notes", {"title": "a"}, self.tok)[1]
        self.assertEqual(call("DELETE", "/notes/%d" % n["id"], token=self.tok)[0], 200)
        self.assertEqual(call("GET", "/notes")[1], [])

    def test_missing(self):
        self.assertEqual(call("DELETE", "/notes/42", token=self.tok)[0], 404)

    def test_empty_title(self):
        self.assertEqual(call("POST", "/notes", {"title": " "}, self.tok)[0], 400)

    def test_long_title(self):
        self.assertEqual(call("POST", "/notes", {"title": "x" * 121}, self.tok)[0], 400)

    def test_bad_json(self):
        self.assertEqual(call("POST", "/notes", raw=b"{", token=self.tok)[0], 400)


if __name__ == "__main__":
    unittest.main()
