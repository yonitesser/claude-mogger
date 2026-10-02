# Reservations service (toy)

A tiny in-memory service. `app/routes.py` maps (METHOD, path) to handler
functions in `app/handlers.py`. Handlers take a payload and return
`(status_code, body_dict)`. State lives in `app/store.py`.

Run the tests: `python3 -m unittest discover -s tests`
