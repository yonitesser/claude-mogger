import unittest

from audience import events, identity, summary


def rows(*emails):
    return [{"email": e} for e in emails]


class HiddenIdentityTests(unittest.TestCase):
    def test_company_domains_keep_dots_and_tags(self):
        self.assertEqual(summary.unique_users(rows("ana.lopez@corp.example", "analopez@corp.example", "ana.lopez+sales@corp.example")), 3)
        self.assertEqual(summary.unique_users(rows("ana@corp.example", "ana+x@corp.example", "ana+y@corp.example")), 3)

    def test_googlemail_is_gmail(self):
        self.assertEqual(summary.unique_users(rows("a.b@gmail.com", "ab+x@googlemail.com", "A.B@GMAIL.COM")), 1)

    def test_case_domain_and_spaces_on_company_domains(self):
        self.assertEqual(summary.unique_users(rows("Ana@Corp.Example", " ana@corp.example ")), 1)
        self.assertEqual(identity.canonical("Ana@Corp.Example"), identity.canonical("ana@corp.example"))

    def test_parse_row_keeps_the_address_as_given(self):
        self.assertEqual(events.parse_row({"email": " Ana.Lopez+Sales@Corp.Example "})["email"], "ana.lopez+sales@corp.example")
        self.assertEqual(events.parse_row({"email": "x@y.example", "action": "login"})["action"], "login")

    def test_by_domain_counts_the_real_domain(self):
        self.assertEqual(summary.signups_by_domain(rows("a+x@corp.example", "b@corp.example")), {"corp.example": 2})


if __name__ == "__main__":
    unittest.main()
