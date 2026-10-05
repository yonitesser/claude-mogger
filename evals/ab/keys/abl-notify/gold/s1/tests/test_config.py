import os
import unittest
from unittest import mock

from notify import config


class ConfigTests(unittest.TestCase):
    def test_reads_env(self):
        with mock.patch.dict(os.environ, {"SLACK_WEBHOOK_URL": "https://x.invalid/a", "WEBHOOK_SECRET": "s"}):
            self.assertEqual(config.load(), {"slack_url": "https://x.invalid/a", "secret": "s"})

    def test_missing_var_named(self):
        with mock.patch.dict(os.environ, {"SLACK_WEBHOOK_URL": "https://x.invalid/a"}, clear=True):
            with self.assertRaises(config.ConfigError) as ctx:
                config.load()
        self.assertIn("WEBHOOK_SECRET", str(ctx.exception))


if __name__ == "__main__":
    unittest.main()
