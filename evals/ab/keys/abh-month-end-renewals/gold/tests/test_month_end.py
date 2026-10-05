import unittest
from datetime import date

from renewals.schedule import renewal_dates


class MonthEndTests(unittest.TestCase):
    def test_no_drift(self):
        self.assertEqual(renewal_dates(date(2023, 1, 31), 3), [date(2023, 1, 31), date(2023, 2, 28), date(2023, 3, 31)])
