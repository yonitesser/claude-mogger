import hashlib
import hmac
import json
import os
import unittest
from unittest import mock

from notify import service


class DuplicateTests(unittest.TestCase):
    def test_same_event_once(self):
        env = {"SLACK_WEBHOOK_URL": "https://x.invalid/slack", "DISCORD_WEBHOOK_URL": "https://x.invalid/d", "WEBHOOK_SECRET": "s"}
        body = json.dumps({"id": "evt_dup_test", "type": "order.paid", "data": {}}).encode()
        sig = {"X-Signature": hmac.new(b"s", body, hashlib.sha256).hexdigest()}
        with mock.patch.dict(os.environ, env), mock.patch("notify.transport.post_json", return_value=200) as post:
            service.handle_webhook(sig, body)
            status, _ = service.handle_webhook(sig, body)
        self.assertEqual(status, 200)
        self.assertEqual(post.call_count, 1)


if __name__ == "__main__":
    unittest.main()
