import unittest

from app.log import warn


class LogTests(unittest.TestCase):
    def test_warn_returns_length(self):
        # prints "FAIL-SOFT: retrying" to stderr; that is expected output, not a failure
        self.assertEqual(warn("retrying"), 8)

    def test_warn_empty(self):
        self.assertEqual(warn(""), 0)


if __name__ == "__main__":
    unittest.main()
