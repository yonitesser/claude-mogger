import os

from sms import http

URL = "https://api.sms-provider.invalid/v2/accounts/%s/messages"
SID = os.environ.get("SMS_SID", "AC9f3b7d1e5a4c2860b1d7e3f5a9c4b82d")
TOKEN = os.environ.get("SMS_TOKEN", "k8Qw3ZpL0vXr7TnB5mYd2HcJ9sUe4GaF")


class MissingCredentials(RuntimeError):
    pass


def send_sms(to, body):
    status, _text = http.post_form(URL % SID, (SID, TOKEN), {"To": to, "Body": body})
    return 200 <= status < 300
