"""Settings come from environment variables (see .env.example). Nothing secret lives in the code."""
import os

REQUIRED = ("SLACK_WEBHOOK_URL", "WEBHOOK_SECRET")


class ConfigError(RuntimeError):
    pass


def load():
    missing = [name for name in REQUIRED if not os.environ.get(name)]
    if missing:
        raise ConfigError("missing environment variable(s): %s (see .env.example)" % ", ".join(missing))
    return {"slack_url": os.environ["SLACK_WEBHOOK_URL"], "secret": os.environ["WEBHOOK_SECRET"]}
