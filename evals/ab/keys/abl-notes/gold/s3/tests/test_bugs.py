import unittest

from tests.helpers import call, login, reset


class BugTests(unittest.TestCase):
    def setUp(self):
        reset()

    def test_ids_stay_unique_after_delete(self):
        tok = login()
        ids = [call("POST", "/notes", {"title": t}, tok)[1]["id"] for t in ("a", "b", "c")]
        call("DELETE", "/notes/%d" % ids[0], token=tok)
        new = call("POST", "/notes", {"title": "d"}, tok)[1]["id"]
        self.assertNotIn(new, ids)
        self.assertEqual(len(call("GET", "/notes")[1]), 3)

    def test_duplicate_email(self):
        login("a@example.org")
        self.assertEqual(call("POST", "/signup", {"email": "a@example.org", "password": "other-pass-1"})[0], 409)


if __name__ == "__main__":
    unittest.main()
