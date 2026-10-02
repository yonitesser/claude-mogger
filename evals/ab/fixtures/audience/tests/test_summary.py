import unittest

from audience import summary


def rows(*emails):
    return [{"email": e} for e in emails]


class SummaryTests(unittest.TestCase):
    def test_case_and_spaces_ignored(self):
        self.assertEqual(summary.unique_users(rows("Bo@Corp.example", " bo@corp.example ")), 1)

    def test_gmail_dots_and_tags_are_the_same_person(self):
        self.assertEqual(summary.unique_users(rows("a.b@gmail.com", "ab@gmail.com", "ab+news@gmail.com")), 1)

    def test_distinct_company_addresses_stay_distinct(self):
        self.assertEqual(summary.unique_users(rows("ana.lopez@corp.example", "analopez@corp.example", "ana.lopez+sales@corp.example")), 3)

    def test_by_domain(self):
        self.assertEqual(summary.signups_by_domain(rows("a@x.example", "b@x.example", "c@y.example")), {"x.example": 2, "y.example": 1})


if __name__ == "__main__":
    unittest.main()
