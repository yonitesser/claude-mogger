import unittest

from tests.helpers import call, login, reset


class AccountTests(unittest.TestCase):
    def setUp(self):
        reset()

    def test_write_needs_login(self):
        self.assertEqual(call("POST", "/notes", {"title": "a"})[0], 401)

    def test_wrong_password(self):
        login("a@example.org")
        self.assertEqual(call("POST", "/login", {"email": "a@example.org", "password": "wrong-password"})[0], 401)

    def test_only_owner_edits(self):
        a, b = login("a@example.org"), login("b@example.org")
        n = call("POST", "/notes", {"title": "mine"}, a)[1]
        self.assertEqual(call("PUT", "/notes/%d" % n["id"], {"title": "x"}, b)[0], 403)
        self.assertEqual(call("DELETE", "/notes/%d" % n["id"], token=b)[0], 403)

    def test_reads_are_public(self):
        call("POST", "/notes", {"title": "mine"}, login())
        self.assertEqual(len(call("GET", "/notes")[1]), 1)


if __name__ == "__main__":
    unittest.main()
