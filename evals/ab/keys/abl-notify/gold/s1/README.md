# notify

Receives order webhooks from our shop provider and posts a message to our team chat.
Python 3 standard library only (the server has no pip access).

- `notify/service.py`: `handle_webhook(headers, raw_body) -> (status, body_dict)` is the entry point.
  `headers` is a dict with canonical names (for example `X-Signature`); `raw_body` is bytes.
- `notify/transport.py`: all outbound HTTP goes through `post_json(url, payload)`, so tests can
  replace it. It returns the HTTP status code and raises `OSError` when the network fails.
- `notify/config.py`: settings, read from environment variables.
- `python3 -m notify.main --check` loads the config and prints `config ok`; without `--check` it
  serves on port 8080.

## Configuration

Set these environment variables (copy `.env.example` to `.env` for local runs and export them):

- `SLACK_WEBHOOK_URL`: where messages go.
- `WEBHOOK_SECRET`: the provider's webhook signing secret.

The app refuses to start and names the missing variable when one is not set.

Events look like `{"id": "evt_123", "type": "order.paid", "data": {"order_id": "A1", "amount_cents": 1250, "customer": "Ana"}}`.
Types: `order.paid`, `order.refunded`, `order.shipped`.

Run tests: `python3 -m unittest discover -s tests`
