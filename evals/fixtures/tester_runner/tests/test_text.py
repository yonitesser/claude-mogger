import unittest

from lib.text import slug


class SlugTests(unittest.TestCase):
    def test_basic(self):
        self.assertEqual(slug(" Hello World "), "hello-world")

    def test_collapses_double_space(self):
        self.assertEqual(slug("a  b"), "a-b")


if __name__ == "__main__":
    unittest.main()
