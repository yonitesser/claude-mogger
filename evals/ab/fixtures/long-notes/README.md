# notes

A small notes API for our team app. Python 3 standard library only (the box it
runs on has no pip access, so no third-party packages).

- `notes/app.py`: `handle(method, path, headers, body) -> (status, headers, body_bytes)`.
  `headers` is a dict with canonical names (`Authorization`, `Content-Type`); `body` is bytes.
  Responses are JSON.
- `notes/store.py`: in-memory storage (`STORE` in app.py).
- `notes/clock.py`: `now()`; use it instead of calling time directly so tests can fake time.
- `server.py`: runs the app on http://localhost:8000 with wsgiref.

Run tests: `python3 -m unittest discover -s tests`

## Roadmap

- edit and delete notes: `PUT /notes/<id>`, `DELETE /notes/<id>`
- accounts: `POST /signup` and `POST /login` with JSON `{"email": ..., "password": ...}`;
  login returns `{"token": ...}`; clients send `Authorization: Bearer <token>`
