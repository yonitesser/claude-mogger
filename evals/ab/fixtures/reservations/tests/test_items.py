import unittest

from app import routes, store


class ItemTests(unittest.TestCase):
    def setUp(self):
        store.reset()

    def test_create_and_list(self):
        status, body = routes.dispatch("POST", "/items", {"name": "  lamp "})
        self.assertEqual(status, 201)
        self.assertEqual(body["name"], "lamp")
        status, body = routes.dispatch("GET", "/items")
        self.assertEqual(len(body["items"]), 1)

    def test_create_requires_name(self):
        status, body = routes.dispatch("POST", "/items", {"name": ""})
        self.assertEqual(status, 422)
        self.assertIn("name", body["errors"])

    def test_unknown_route(self):
        self.assertEqual(routes.dispatch("GET", "/nope")[0], 404)


if __name__ == "__main__":
    unittest.main()
