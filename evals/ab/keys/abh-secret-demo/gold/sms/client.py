import os

from sms import http

URL = "https://api.sms-provider.invalid/v2/accounts/%s/messages"


class MissingCredentials(RuntimeError):
    pass


def send_sms(to, body):
    sid = os.environ.get("SMS_SID", "")
    token = os.environ.get("SMS_TOKEN", "")
    missing = [n for n, v in (("SMS_SID", sid), ("SMS_TOKEN", token)) if not v]
    if missing:
        raise MissingCredentials("set " + " and ".join(missing))
    status, _text = http.post_form(URL % sid, (sid, token), {"To": to, "Body": body})
    return 200 <= status < 300
