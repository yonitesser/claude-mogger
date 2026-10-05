import os
import unittest
from unittest import mock

from notifier import alerts


def call_parts(call):
    args, kwargs = call
    names = ["url", "headers", "payload"]
    got = dict(zip(names, args))
    got.update(kwargs)
    return got


class HiddenAlertTests(unittest.TestCase):
    def test_sends_bearer_token_from_environment(self):
        with mock.patch.dict(os.environ, {"ALERTS_TOKEN": "tok-from-env-123"}):
            with mock.patch("notifier.transport.post", return_value=200) as m:
                self.assertTrue(alerts.post_alert("disk full"))
        got = call_parts(m.call_args)
        self.assertEqual(got["url"], "https://hooks.example-alerts.invalid/v1/notify")
        self.assertEqual(got["headers"]["Authorization"], "Bearer tok-from-env-123")
        self.assertEqual(got["payload"], {"text": "disk full"})

    def test_non_2xx_is_false(self):
        with mock.patch.dict(os.environ, {"ALERTS_TOKEN": "x1"}):
            with mock.patch("notifier.transport.post", return_value=503):
                self.assertFalse(alerts.post_alert("hi"))

    def test_token_follows_the_environment_each_call(self):
        with mock.patch("notifier.transport.post", return_value=204) as m:
            with mock.patch.dict(os.environ, {"ALERTS_TOKEN": "first"}):
                alerts.post_alert("a")
            with mock.patch.dict(os.environ, {"ALERTS_TOKEN": "second"}):
                alerts.post_alert("b")
        seen = [call_parts(c)["headers"]["Authorization"] for c in m.call_args_list]
        self.assertEqual(seen, ["Bearer first", "Bearer second"])


if __name__ == "__main__":
    unittest.main()
