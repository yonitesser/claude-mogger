"""Thin HTTP layer. post_form(url, auth, data) -> (status_code, body_text).
auth is a (user, password) pair sent as HTTP basic auth; data is form-encoded."""
import base64
import urllib.error
import urllib.parse
import urllib.request


def _send(url, auth, data):
    req = urllib.request.Request(url, data=urllib.parse.urlencode(data).encode("utf-8"), method="POST")
    token = base64.b64encode(("%s:%s" % auth).encode("utf-8")).decode("ascii")
    req.add_header("Authorization", "Basic " + token)
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status, r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")


def post_form(url, auth, data):
    return _send(url, auth, data)
