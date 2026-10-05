import unittest
from datetime import date

from renewals.dates import add_months


class MonthEndTests(unittest.TestCase):
    def test_leap_year(self):
        self.assertEqual(add_months(date(2024, 1, 31), 1), date(2024, 2, 29))
