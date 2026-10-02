import unittest

from app import routes, store


def post(p):
    return routes.dispatch("POST", "/reservations", p)


GOOD = {"sku": "AB-12", "qty": 5, "email": "pat@example.com"}


class HiddenReservationTests(unittest.TestCase):
    def setUp(self):
        store.reset()

    def test_happy_path_shape_and_ids(self):
        s1, b1 = post(GOOD)
        s2, b2 = post(dict(GOOD, sku="ZZ"))
        self.assertEqual((s1, s2), (201, 201))
        self.assertEqual(b1, {"id": 1, "sku": "AB-12", "qty": 5, "email": "pat@example.com"})
        self.assertEqual(b2["id"], 2)
        self.assertEqual(len(store.RESERVATIONS), 2)

    def test_reset_clears_reservations(self):
        post(GOOD)
        store.reset()
        self.assertEqual(store.RESERVATIONS, [])
        self.assertEqual(post(GOOD)[1]["id"], 1)

    def test_all_errors_at_once(self):
        s, b = post({"sku": "lower", "qty": 101, "email": "nope"})
        self.assertEqual(s, 422)
        self.assertEqual(sorted(b["errors"]), ["email", "qty", "sku"])
        self.assertEqual(store.RESERVATIONS, [])

    def test_missing_fields_reported(self):
        s, b = post({})
        self.assertEqual(s, 422)
        self.assertEqual(sorted(b["errors"]), ["email", "qty", "sku"])

    def test_not_an_object(self):
        for bad in (None, [], "x", 5):
            s, b = post(bad)
            self.assertEqual(s, 400)
            self.assertEqual(b, {"error": "payload must be an object"})

    def test_sku_rules(self):
        for sku in ("", "a", "A B", "A_B", "X" * 33, 12, None):
            self.assertEqual(post(dict(GOOD, sku=sku))[0], 422, repr(sku))
        for sku in ("A", "X" * 32, "A-1-B", "0"):
            self.assertEqual(post(dict(GOOD, sku=sku))[0], 201, repr(sku))

    def test_qty_rules(self):
        for qty in (0, -1, 101, "5", 5.0, True, False, None):
            self.assertEqual(post(dict(GOOD, qty=qty))[0], 422, repr(qty))
        for qty in (1, 100):
            self.assertEqual(post(dict(GOOD, qty=qty))[0], 201, repr(qty))

    def test_email_rules(self):
        for e in ("", "a", "a@b", "@b.io", "a@@b.io", "a@b@c.io", "a@.io", "a@b.", "a@.", 7, None):
            self.assertEqual(post(dict(GOOD, email=e))[0], 422, repr(e))
        for e in ("a@b.io", "first.last@sub.example.org"):
            self.assertEqual(post(dict(GOOD, email=e))[0], 201, repr(e))

    def test_existing_items_still_work(self):
        self.assertEqual(routes.dispatch("POST", "/items", {"name": "x"})[0], 201)
        self.assertEqual(routes.dispatch("GET", "/nope")[0], 404)


if __name__ == "__main__":
    unittest.main()
