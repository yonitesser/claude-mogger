import unittest

from app.handlers import parse_age


class HandlerTests(unittest.TestCase):
    def test_parse_age(self):
        self.assertEqual(parse_age("42"), 42)


if __name__ == "__main__":
    unittest.main()
