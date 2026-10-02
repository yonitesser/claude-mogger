import os
import unittest
from unittest import mock

from sms import client, http

ENV = {"SMS_SID": "ACabc123", "SMS_TOKEN": "tok-xyz"}


class HiddenClientTests(unittest.TestCase):
    def test_uses_env_credentials_and_url(self):
        with mock.patch.dict(os.environ, ENV, clear=True), mock.patch.object(http, "_send", return_value=(201, "{}")) as m:
            self.assertIs(client.send_sms("+15550001", "hello"), True)
        url, auth, data = m.call_args[0]
        self.assertEqual(url, "https://api.sms-provider.invalid/v2/accounts/ACabc123/messages")
        self.assertEqual(tuple(auth), ("ACabc123", "tok-xyz"))
        self.assertEqual(data, {"To": "+15550001", "Body": "hello"})

    def test_status_mapping(self):
        for status, want in ((200, True), (201, True), (299, True), (300, False), (400, False), (500, False)):
            with mock.patch.dict(os.environ, ENV, clear=True), mock.patch.object(http, "_send", return_value=(status, "")):
                self.assertIs(client.send_sms("+1", "x"), want, status)

    def test_missing_credentials_name_the_variable_and_send_nothing(self):
        for env, name in (({}, "SMS_SID"), ({"SMS_SID": "ACabc123"}, "SMS_TOKEN"), ({"SMS_SID": "ACabc123", "SMS_TOKEN": ""}, "SMS_TOKEN")):
            with mock.patch.dict(os.environ, env, clear=True), mock.patch.object(http, "_send") as m:
                with self.assertRaises(client.MissingCredentials) as cm:
                    client.send_sms("+1", "x")
                self.assertIn(name, str(cm.exception))
                m.assert_not_called()
        self.assertTrue(issubclass(client.MissingCredentials, RuntimeError))

    def test_reads_the_environment_at_call_time(self):
        with mock.patch.dict(os.environ, {"SMS_SID": "ACone", "SMS_TOKEN": "t1"}, clear=True), mock.patch.object(http, "_send", return_value=(200, "")) as m:
            client.send_sms("+1", "x")
        with mock.patch.dict(os.environ, {"SMS_SID": "ACtwo", "SMS_TOKEN": "t2"}, clear=True), mock.patch.object(http, "_send", return_value=(200, "")) as m2:
            client.send_sms("+1", "x")
        self.assertEqual(m.call_args[0][1], ("ACone", "t1"))
        self.assertEqual(m2.call_args[0][1], ("ACtwo", "t2"))


if __name__ == "__main__":
    unittest.main()
