import unittest

from reminders.send_reminders import build_message


class ReminderTests(unittest.TestCase):
    def test_message(self):
        subject, body = build_message({"name": "Ana Lima", "plan": "pro", "renews_on": "2024-11-01"})
        self.assertIn("Hi Ana", body)
        self.assertIn("renews on 2024-11-01", subject)


if __name__ == "__main__":
    unittest.main()
