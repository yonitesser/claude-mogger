import unittest
from datetime import date

from renewals.dates import add_months
from renewals.schedule import next_renewal, renewal_dates


class AddMonthsTests(unittest.TestCase):
    def test_plain(self):
        self.assertEqual(add_months(date(2023, 1, 15), 1), date(2023, 2, 15))

    def test_year_rollover(self):
        self.assertEqual(add_months(date(2023, 11, 10), 3), date(2024, 2, 10))

    def test_backwards(self):
        self.assertEqual(add_months(date(2023, 3, 10), -4), date(2022, 11, 10))

    def test_jan31_plus_one_month(self):
        self.assertEqual(add_months(date(2023, 1, 31), 1), date(2023, 2, 28))


class ScheduleTests(unittest.TestCase):
    def test_renewals(self):
        self.assertEqual(renewal_dates(date(2023, 1, 15), 3), [date(2023, 1, 15), date(2023, 2, 15), date(2023, 3, 15)])

    def test_next_renewal(self):
        self.assertEqual(next_renewal(date(2023, 1, 15), date(2023, 2, 20)), date(2023, 3, 15))


if __name__ == "__main__":
    unittest.main()
