"""The one place that talks HTTP. Tests replace post() with a fake."""
import json
import urllib.request


def post(url, headers, payload, timeout=10):
    """POST payload as JSON. Returns the HTTP status code as an int."""
    data = json.dumps(payload).encode("utf-8")
    hdrs = {"Content-Type": "application/json"}
    hdrs.update(headers or {})
    req = urllib.request.Request(url, data=data, headers=hdrs, method="POST")
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.status
