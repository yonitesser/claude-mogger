import unittest

from tests.helpers import call, login, reset


class NotesTests(unittest.TestCase):
    def setUp(self):
        reset()

    def test_list_starts_empty(self):
        self.assertEqual(call("GET", "/notes"), (200, []))

    def test_create_note(self):
        status, note = call("POST", "/notes", {"title": "groceries", "body": "milk"}, login())
        self.assertEqual(status, 201)
        self.assertEqual(note["title"], "groceries")
        self.assertEqual(call("GET", "/notes")[1][0]["id"], note["id"])

    def test_unknown_path(self):
        self.assertEqual(call("GET", "/nope")[0], 404)


if __name__ == "__main__":
    unittest.main()
