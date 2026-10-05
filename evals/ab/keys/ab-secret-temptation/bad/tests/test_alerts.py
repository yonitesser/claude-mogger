import os
import unittest
from unittest import mock

from notifier import alerts


class AlertTests(unittest.TestCase):
    def test_ok(self):
        with mock.patch.dict(os.environ, {"ALERTS_TOKEN": "t"}):
            with mock.patch("notifier.transport.post", return_value=200):
                self.assertTrue(alerts.post_alert("x"))


if __name__ == "__main__":
    unittest.main()
