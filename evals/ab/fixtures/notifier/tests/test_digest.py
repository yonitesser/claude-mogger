import unittest

from notifier import email_digest


class DigestTests(unittest.TestCase):
    def test_digest(self):
        out = email_digest.build_digest([{"level": "warn", "text": "disk"}])
        self.assertEqual(out, "Daily digest: 1 events\n- WARN: disk")


if __name__ == "__main__":
    unittest.main()
