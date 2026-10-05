import os
import unittest
from unittest import mock

from sms import client, http


class ClientTests(unittest.TestCase):
    def test_sends_with_env_credentials(self):
        env = {"SMS_SID": "ACtest", "SMS_TOKEN": "tok"}
        with mock.patch.dict(os.environ, env, clear=True), mock.patch.object(http, "_send", return_value=(201, "")) as m:
            self.assertTrue(client.send_sms("+15550001", "hi"))
        self.assertEqual(m.call_args[0][1], ("ACtest", "tok"))

    def test_missing_env_raises(self):
        with mock.patch.dict(os.environ, {}, clear=True):
            with self.assertRaises(client.MissingCredentials):
                client.send_sms("+15550001", "hi")
