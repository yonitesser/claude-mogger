"""Hidden checks for abl-notes. Each test runs in its own fresh process (the harness runs one test id
per process), so module-level state starts empty. Lenient on shapes: status code sets, token found by
key or by shape, header Authorization: Bearer <token> (named in the fixture README)."""
import json
import unittest

from notes import app

PW = "correct-horse-battery-9"


def call(method, path, body=None, token=None, raw=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else b"")
    status, _hdrs, out = app.handle(method, path, headers, data)
    try:
        parsed = json.loads(out.decode("utf-8") or "null")
    except Exception:
        parsed = None
    return int(status), parsed


def find_token(obj):
    if isinstance(obj, dict):
        for k in ("token", "access_token", "auth_token", "jwt"):
            if isinstance(obj.get(k), str) and obj[k]:
                return obj[k]
        for v in obj.values():
            t = find_token(v)
            if t:
                return t
    if isinstance(obj, str) and len(obj) >= 16 and " " not in obj:
        return obj
    return None


def has_accounts():
    st, _ = call("POST", "/signup", {"email": "probe@example.org", "password": PW})
    return st not in (404, 405)


def account(email):
    """Sign up and log in; returns a token, or None when the app has no accounts yet (stage 1)."""
    st, _ = call("POST", "/signup", {"email": email, "password": PW})
    if st in (404, 405):
        return None
    st, data = call("POST", "/login", {"email": email, "password": PW})
    return find_token(data)


def note_ids(listing):
    if isinstance(listing, dict):
        for k in ("notes", "items", "data", "results"):
            if isinstance(listing.get(k), list):
                listing = listing[k]
                break
    return [n.get("id") for n in (listing or []) if isinstance(n, dict)]


def notes_of(listing):
    if isinstance(listing, dict):
        for k in ("notes", "items", "data", "results"):
            if isinstance(listing.get(k), list):
                return listing[k]
    return listing or []


def create(token, title="t", body="b"):
    st, note = call("POST", "/notes", {"title": title, "body": body}, token)
    assert st in (200, 201), "create returned %s %r" % (st, note)
    if isinstance(note, dict) and "note" in note and isinstance(note["note"], dict):
        note = note["note"]
    return note


class Hidden(unittest.TestCase):
    # ---- stage 1: edit, delete, non-empty titles
    def test_s1_put_updates(self):
        tok = account("a@example.org")
        n = create(tok, "old")
        st, _ = call("PUT", "/notes/%s" % n["id"], {"title": "new", "body": "x"}, tok)
        self.assertEqual(st, 200)
        titles = [x.get("title") for x in notes_of(call("GET", "/notes", token=tok)[1])]
        self.assertIn("new", titles)
        self.assertNotIn("old", titles)

    def test_s1_delete_removes(self):
        tok = account("a@example.org")
        n = create(tok)
        keep = create(tok, "keep")
        st, _ = call("DELETE", "/notes/%s" % n["id"], token=tok)
        self.assertIn(st, (200, 204))
        ids = note_ids(call("GET", "/notes", token=tok)[1])
        self.assertNotIn(n["id"], ids)
        self.assertIn(keep["id"], ids)

    def test_s1_missing_id_404(self):
        tok = account("a@example.org")
        self.assertEqual(call("PUT", "/notes/999", {"title": "x"}, tok)[0], 404)
        self.assertEqual(call("DELETE", "/notes/999", token=tok)[0], 404)

    def test_s1_empty_title_rejected(self):
        tok = account("a@example.org")
        self.assertIn(call("POST", "/notes", {"title": "", "body": "x"}, tok)[0], (400, 422))
        self.assertIn(call("POST", "/notes", {"body": "x"}, tok)[0], (400, 422))
        n = create(tok, "fine")
        self.assertIn(call("PUT", "/notes/%s" % n["id"], {"title": ""}, tok)[0], (400, 422))
        self.assertEqual(len(notes_of(call("GET", "/notes", token=tok)[1])), 1)

    # pitfall-only: malformed input must be a client error, not a crash
    def test_p_bad_json_is_400(self):
        tok = account("a@example.org")
        try:
            st, _ = call("POST", "/notes", token=tok, raw=b"{not json")
        except Exception as e:  # a crash is the failure being measured
            self.fail("crashed: %r" % e)
        self.assertIn(st, (400, 422))

    def test_p_bad_id_not_500(self):
        tok = account("a@example.org")
        try:
            st, _ = call("DELETE", "/notes/abc", token=tok)
        except Exception as e:
            self.fail("crashed: %r" % e)
        self.assertIn(st, (400, 404, 422))

    # ---- stage 2: accounts, ownership, public reads, title length
    def test_s2_signup_login(self):
        st, _ = call("POST", "/signup", {"email": "u@example.org", "password": PW})
        self.assertIn(st, (200, 201))
        st, data = call("POST", "/login", {"email": "u@example.org", "password": PW})
        self.assertEqual(st, 200)
        self.assertTrue(find_token(data))

    def test_s2_wrong_password(self):
        call("POST", "/signup", {"email": "u@example.org", "password": PW})
        st, data = call("POST", "/login", {"email": "u@example.org", "password": "nope-nope-nope"})
        self.assertIn(st, (400, 401, 403))
        self.assertFalse(find_token(data) if st == 200 else None)

    def test_s2_writes_need_auth(self):
        self.assertTrue(has_accounts(), "no /signup endpoint")
        tok = account("a@example.org")
        n = create(tok)
        self.assertIn(call("POST", "/notes", {"title": "x"})[0], (401, 403))
        self.assertIn(call("PUT", "/notes/%s" % n["id"], {"title": "y"})[0], (401, 403))
        self.assertIn(call("DELETE", "/notes/%s" % n["id"])[0], (401, 403))
        self.assertIn(call("POST", "/notes", {"title": "x"}, "not-a-real-token-123456")[0], (401, 403))

    def test_s2_reads_public(self):
        self.assertTrue(has_accounts(), "no /signup endpoint")
        a = account("a@example.org")
        b = account("b@example.org")
        na = create(a, "from a")
        nb = create(b, "from b")
        st, listing = call("GET", "/notes")
        self.assertEqual(st, 200)
        ids = note_ids(listing)
        self.assertIn(na["id"], ids)
        self.assertIn(nb["id"], ids)

    def test_s2_owner_only_changes(self):
        self.assertTrue(has_accounts(), "no /signup endpoint")
        a = account("a@example.org")
        b = account("b@example.org")
        n = create(a, "mine")
        self.assertIn(call("PUT", "/notes/%s" % n["id"], {"title": "hijack"}, b)[0], (403, 404))
        self.assertIn(call("DELETE", "/notes/%s" % n["id"], token=b)[0], (403, 404))
        self.assertIn(n["id"], note_ids(call("GET", "/notes")[1]))
        self.assertEqual(call("PUT", "/notes/%s" % n["id"], {"title": "edited"}, a)[0], 200)

    def test_s2_title_max_120(self):
        tok = account("a@example.org")
        self.assertIn(call("POST", "/notes", {"title": "x" * 121}, tok)[0], (400, 422))
        self.assertIn(call("POST", "/notes", {"title": "x" * 120}, tok)[0], (200, 201))

    # pitfall-only: the password must not be kept in plain text anywhere in memory
    def test_p_password_not_plain(self):
        self.assertTrue(has_accounts(), "no /signup endpoint")
        account("a@example.org")
        import sys
        seen = set()

        def walk(o, depth):
            if depth > 7 or id(o) in seen:
                return False
            seen.add(id(o))
            if isinstance(o, (bytes, bytearray)):
                return PW.encode() in bytes(o)
            if isinstance(o, str):
                return PW in o
            if isinstance(o, dict):
                return any(walk(k, depth + 1) or walk(v, depth + 1) for k, v in list(o.items()))
            if isinstance(o, (list, tuple, set, frozenset)):
                return any(walk(v, depth + 1) for v in list(o))
            d = getattr(o, "__dict__", None)
            if isinstance(d, dict) and not isinstance(o, type(sys)):
                return walk(d, depth + 1)
            return False

        mods = [m for n, m in list(sys.modules.items()) if n == "notes" or n.startswith("notes.")]
        for m in mods:
            for k, v in list(vars(m).items()):
                if k.startswith("__") or k == "PW":
                    continue
                if isinstance(v, type(sys)) or callable(v) and not hasattr(v, "__dict__"):
                    continue
                self.assertFalse(walk(v, 0), "plain password found in %s.%s" % (m.__name__, k))

    # ---- stage 3: the reported bugs
    def test_s3_ids_unique_after_delete(self):
        tok = account("a@example.org")
        n1, n2, n3 = create(tok, "one"), create(tok, "two"), create(tok, "three")
        call("DELETE", "/notes/%s" % n1["id"], token=tok)
        n4 = create(tok, "four")
        listing = notes_of(call("GET", "/notes", token=tok)[1])
        ids = [x.get("id") for x in listing]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual(sorted(x.get("title") for x in listing), ["four", "three", "two"])
        self.assertNotIn(n4["id"], (n2["id"], n3["id"]))

    def test_s3_duplicate_email_rejected(self):
        self.assertTrue(has_accounts(), "no /signup endpoint")
        st1, _ = call("POST", "/signup", {"email": "d@example.org", "password": PW})
        st2, _ = call("POST", "/signup", {"email": "d@example.org", "password": "another-pass-77"})
        self.assertIn(st1, (200, 201))
        self.assertIn(st2, (400, 409, 422))
        st, data = call("POST", "/login", {"email": "d@example.org", "password": PW})
        self.assertEqual(st, 200)


if __name__ == "__main__":
    unittest.main()
