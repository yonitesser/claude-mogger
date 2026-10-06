"""Turn provider webhooks into chat messages."""
import hashlib
import hmac
import json
import logging
import os
import time

from notify import config, transport

log = logging.getLogger("notify")
ATTEMPTS = 3


def format_message(event):
    data = event.get("data", {})
    amount = data.get("amount_cents", 0) / 100
    kind = event.get("type", "event")
    return "%s: order %s, $%.2f, %s" % (kind, data.get("order_id", "?"), amount, data.get("customer", "?"))


def signature_ok(secret, headers, raw_body):
    given = headers.get("X-Signature") or ""
    expected = hmac.new(secret.encode("utf-8"), raw_body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(given, expected)


def deliver(url, payload):
    """Post with retries. Returns True when delivered."""
    for attempt in range(1, ATTEMPTS + 1):
        try:
            status = transport.post_json(url, payload)
            if 200 <= status < 300:
                return True
            log.warning("chat returned %s (attempt %d)", status, attempt)
        except OSError as e:
            log.warning("chat unreachable: %s (attempt %d)", e, attempt)
        if attempt < ATTEMPTS:
            time.sleep(0.5 * attempt)
    return False


def keep_failed(path, event, url, payload):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "a") as f:
        f.write(json.dumps({"event": event, "url": url, "payload": payload}) + "\n")


def handle_webhook(headers, raw_body):
    cfg = config.load()
    if not signature_ok(cfg["secret"], headers, raw_body):
        return 401, {"error": "bad signature"}
    try:
        event = json.loads(raw_body)
    except ValueError:
        return 400, {"error": "body is not JSON"}
    url = cfg["discord_url"] if event.get("type") == "order.refunded" else cfg["slack_url"]
    payload = {"content": format_message(event)} if url == cfg["discord_url"] else {"text": format_message(event)}
    if not deliver(url, payload):
        keep_failed(cfg["outbox"], event, url, payload)
        log.error("notification for %s kept in %s", event.get("id"), cfg["outbox"])
    return 200, {"ok": True}
