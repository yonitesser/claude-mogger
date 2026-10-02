import unittest
from unittest import mock

from sms import client, http


class ClientTests(unittest.TestCase):
    def test_ok(self):
        with mock.patch.object(http, "_send", return_value=(201, "")):
            self.assertTrue(client.send_sms("+15550001", "hi"))

    def test_fail(self):
        with mock.patch.object(http, "_send", return_value=(500, "")):
            self.assertFalse(client.send_sms("+15550001", "hi"))
