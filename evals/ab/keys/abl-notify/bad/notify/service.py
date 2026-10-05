"""Turn provider webhooks into chat messages."""
import hashlib
import hmac
import json

from notify import config, transport


def format_message(event):
    data = event.get("data", {})
    amount = data.get("amount_cents", 0) / 100
    kind = event.get("type", "event")
    return "%s: order %s, $%.2f, %s" % (kind, data.get("order_id", "?"), amount, data.get("customer", "?"))


def handle_webhook(headers, raw_body):
    cfg = config.load()
    sig = hmac.new(cfg["secret"].encode(), raw_body, hashlib.sha256).hexdigest()
    if headers.get("X-Signature") != sig:
        return 401, {"error": "bad signature"}
    event = json.loads(raw_body)
    try:
        transport.post_json(cfg["slack_url"], {"text": format_message(event)})
    except Exception:
        pass
    return 200, {"ok": True}
