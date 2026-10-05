import unittest

from reminders.send_reminders import build_message


class Hidden(unittest.TestCase):
    def test_s1_no_name_no_crash(self):
        for name in ("", "   "):
            subject, body = build_message({"name": name, "email": "x@acme-mail.test", "plan": "pro", "renews_on": "2024-11-03"})
            self.assertIn("2024-11-03", subject + body)
            self.assertNotIn("Hi ,", body)

    def test_s1_named_unchanged(self):
        subject, body = build_message({"name": "Ana Lima", "email": "a@acme-mail.test", "plan": "pro", "renews_on": "2024-11-01"})
        self.assertIn("Hi Ana", body)


if __name__ == "__main__":
    unittest.main()
