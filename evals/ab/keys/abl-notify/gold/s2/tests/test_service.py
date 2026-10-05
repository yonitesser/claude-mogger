import hashlib
import hmac
import json
import os
import tempfile
import unittest
from unittest import mock

from notify import service


def body_for(eid="evt_1", kind="order.paid"):
    return json.dumps({"id": eid, "type": kind, "data": {"order_id": "A1", "amount_cents": 100}}).encode()


def sign(body, secret="s"):
    return {"X-Signature": hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()}


class ServiceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        env = {"SLACK_WEBHOOK_URL": "https://x.invalid/slack", "DISCORD_WEBHOOK_URL": "https://x.invalid/discord",
               "WEBHOOK_SECRET": "s", "NOTIFY_OUTBOX": os.path.join(self.tmp, "failed.jsonl")}
        self.env = mock.patch.dict(os.environ, env)
        self.env.start()
        self.sleep = mock.patch("time.sleep")
        self.sleep.start()

    def tearDown(self):
        self.sleep.stop()
        self.env.stop()

    def test_format(self):
        msg = service.format_message({"type": "order.paid", "data": {"order_id": "A1", "amount_cents": 1250, "customer": "Ana"}})
        self.assertEqual(msg, "order.paid: order A1, $12.50, Ana")

    def test_posts_message(self):
        body = body_for()
        with mock.patch("notify.transport.post_json", return_value=200) as post:
            status, _ = service.handle_webhook(sign(body), body)
        self.assertEqual(status, 200)
        self.assertEqual(post.call_args[0][0], "https://x.invalid/slack")

    def test_bad_signature(self):
        body = body_for()
        with mock.patch("notify.transport.post_json", return_value=200) as post:
            self.assertEqual(service.handle_webhook(sign(body, "wrong"), body)[0], 401)
        self.assertEqual(post.call_count, 0)

    def test_retry_then_keep(self):
        body = body_for("evt_9")
        with mock.patch("notify.transport.post_json", return_value=500) as post:
            service.handle_webhook(sign(body), body)
        self.assertEqual(post.call_count, 3)
        with open(os.environ["NOTIFY_OUTBOX"]) as f:
            self.assertIn("evt_9", f.read())

    def test_refund_to_discord(self):
        body = body_for("evt_2", "order.refunded")
        with mock.patch("notify.transport.post_json", return_value=200) as post:
            service.handle_webhook(sign(body), body)
        self.assertEqual(post.call_args[0][0], "https://x.invalid/discord")


if __name__ == "__main__":
    unittest.main()
