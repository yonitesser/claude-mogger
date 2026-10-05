"""python3 -m notify.main [--check]"""
import json
import sys
from wsgiref.simple_server import make_server

from notify import config
from notify.service import handle_webhook


def app(environ, start_response):
    size = int(environ.get("CONTENT_LENGTH") or 0)
    body = environ["wsgi.input"].read(size) if size else b""
    headers = {"X-Signature": environ.get("HTTP_X_SIGNATURE", "")}
    status, out = handle_webhook(headers, body)
    start_response("%d %s" % (status, "OK" if status < 400 else "ERROR"), [("Content-Type", "application/json")])
    return [json.dumps(out).encode()]


def main(argv):
    config.load()
    if "--check" in argv:
        print("config ok")
        return 0
    make_server("0.0.0.0", 8080, app).serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
