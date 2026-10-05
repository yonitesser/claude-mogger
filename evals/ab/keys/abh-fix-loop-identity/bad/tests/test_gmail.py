import unittest

from audience.identity import canonical


class GmailTests(unittest.TestCase):
    def test_company_dots_kept(self):
        self.assertNotEqual(canonical("a.b@corp.example"), canonical("ab@corp.example"))
