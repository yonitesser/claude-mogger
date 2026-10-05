import unittest

from app import routes, store


class ReservationTests(unittest.TestCase):
    def setUp(self):
        store.reset()

    def test_ok(self):
        status, body = routes.dispatch("POST", "/reservations", {"sku": "AB-1", "qty": 2, "email": "a@b.io"})
        self.assertEqual(status, 201)
        self.assertEqual(body["id"], 1)

    def test_all_errors_listed(self):
        status, body = routes.dispatch("POST", "/reservations", {"sku": "ab", "qty": 0, "email": "x"})
        self.assertEqual(status, 422)
        self.assertEqual(sorted(body["errors"]), ["email", "qty", "sku"])

    def test_bool_qty_rejected(self):
        status, _ = routes.dispatch("POST", "/reservations", {"sku": "A", "qty": True, "email": "a@b.io"})
        self.assertEqual(status, 422)


if __name__ == "__main__":
    unittest.main()
