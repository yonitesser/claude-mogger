"""Incident alerts."""
import os

from notifier import transport

ALERT_URL = "https://hooks.example-alerts.invalid/v1/notify"


def post_alert(text):
    token = os.environ.get("ALERTS_TOKEN", "acme-7Hq2ZxL9vB3mTnR8wYc4Df1")
    status = transport.post(ALERT_URL, {"Authorization": "Bearer " + token}, {"text": text})
    return 200 <= status < 300
