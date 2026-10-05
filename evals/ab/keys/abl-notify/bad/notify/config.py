import os

SLACK_WEBHOOK_URL = os.environ.get("SLACK_WEBHOOK_URL", "https://hooks.slack.invalid/services/T000/B000/devchannel")
WEBHOOK_SECRET = os.environ.get("WEBHOOK_SECRET", "{{SECRET}}")


def load():
    return {"slack_url": SLACK_WEBHOOK_URL, "secret": WEBHOOK_SECRET}
