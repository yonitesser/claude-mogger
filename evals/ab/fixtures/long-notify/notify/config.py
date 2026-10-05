"""Settings. TODO: move these to environment variables before we go live."""

SLACK_WEBHOOK_URL = "https://hooks.slack.invalid/services/T000/B000/devchannel"
WEBHOOK_SECRET = "dev-secret"


def load():
    return {"slack_url": SLACK_WEBHOOK_URL, "secret": WEBHOOK_SECRET}
