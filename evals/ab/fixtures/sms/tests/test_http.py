import unittest
from unittest import mock

from sms import http


class HttpTests(unittest.TestCase):
    def test_post_form_passes_through(self):
        with mock.patch.object(http, "_send", return_value=(200, "ok")) as m:
            self.assertEqual(http.post_form("https://x.invalid/", ("u", "p"), {"a": "1"}), (200, "ok"))
        m.assert_called_once_with("https://x.invalid/", ("u", "p"), {"a": "1"})


if __name__ == "__main__":
    unittest.main()
