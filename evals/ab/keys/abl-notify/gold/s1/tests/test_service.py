import json
import os
import unittest
from unittest import mock

from notify import service

ENV = {"SLACK_WEBHOOK_URL": "https://x.invalid/slack", "WEBHOOK_SECRET": "s"}


class ServiceTests(unittest.TestCase):
    def test_format(self):
        msg = service.format_message({"type": "order.paid", "data": {"order_id": "A1", "amount_cents": 1250, "customer": "Ana"}})
        self.assertEqual(msg, "order.paid: order A1, $12.50, Ana")

    def test_posts_message(self):
        body = json.dumps({"id": "evt_1", "type": "order.paid", "data": {"order_id": "A1", "amount_cents": 100}}).encode()
        with mock.patch.dict(os.environ, ENV), mock.patch("notify.transport.post_json", return_value=200) as post:
            status, _ = service.handle_webhook({}, body)
        self.assertEqual(status, 200)
        self.assertEqual(post.call_args[0][0], "https://x.invalid/slack")


if __name__ == "__main__":
    unittest.main()
