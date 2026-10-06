"""Turn provider webhooks into chat messages."""
import json

from notify import config, transport


def format_message(event):
    data = event.get("data", {})
    amount = data.get("amount_cents", 0) / 100
    kind = event.get("type", "event")
    return "%s: order %s, $%.2f, %s" % (kind, data.get("order_id", "?"), amount, data.get("customer", "?"))


def handle_webhook(headers, raw_body):
    cfg = config.load()
    event = json.loads(raw_body)
    transport.post_json(cfg["slack_url"], {"text": format_message(event)})
    return 200, {"ok": True}
