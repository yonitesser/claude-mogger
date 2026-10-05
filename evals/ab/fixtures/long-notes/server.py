"""Run the notes API locally: python3 server.py"""
from wsgiref.simple_server import make_server

from notes.app import handle


def wsgi(environ, start_response):
    size = int(environ.get("CONTENT_LENGTH") or 0)
    body = environ["wsgi.input"].read(size) if size else b""
    headers = {"Content-Type": environ.get("CONTENT_TYPE", ""), "Authorization": environ.get("HTTP_AUTHORIZATION", "")}
    status, hdrs, out = handle(environ["REQUEST_METHOD"], environ.get("PATH_INFO", "/"), headers, body)
    start_response("%d %s" % (status, "OK" if status < 400 else "ERROR"), list(hdrs.items()))
    return [out]


if __name__ == "__main__":
    make_server("localhost", 8000, wsgi).serve_forever()
