import unittest
from datetime import date

from renewals.dates import add_months
from renewals.schedule import next_renewal, renewal_dates


class HiddenRenewalTests(unittest.TestCase):
    def test_clamps_to_last_day_of_the_target_month(self):
        self.assertEqual(add_months(date(2023, 1, 31), 1), date(2023, 2, 28))
        self.assertEqual(add_months(date(2024, 1, 31), 1), date(2024, 2, 29))
        self.assertEqual(add_months(date(2024, 1, 30), 1), date(2024, 2, 29))
        self.assertEqual(add_months(date(2023, 3, 31), 1), date(2023, 4, 30))
        self.assertEqual(add_months(date(2023, 5, 31), -1), date(2023, 4, 30))
        self.assertEqual(add_months(date(2023, 8, 31), 6), date(2024, 2, 29))

    def test_ordinary_dates_unchanged(self):
        self.assertEqual(add_months(date(2023, 1, 28), 1), date(2023, 2, 28))
        self.assertEqual(add_months(date(2023, 12, 31), 2), date(2024, 2, 29))
        self.assertEqual(add_months(date(2023, 12, 15), 0), date(2023, 12, 15))

    def test_month_end_signup_does_not_drift(self):
        self.assertEqual(renewal_dates(date(2023, 1, 31), 5),
                         [date(2023, 1, 31), date(2023, 2, 28), date(2023, 3, 31), date(2023, 4, 30), date(2023, 5, 31)])
        self.assertEqual(renewal_dates(date(2024, 1, 30), 3), [date(2024, 1, 30), date(2024, 2, 29), date(2024, 3, 30)])

    def test_single_and_first_date(self):
        self.assertEqual(renewal_dates(date(2023, 1, 31), 1), [date(2023, 1, 31)])

    def test_next_renewal_for_month_end(self):
        self.assertEqual(next_renewal(date(2023, 1, 31), date(2023, 3, 1)), date(2023, 3, 31))
        self.assertEqual(next_renewal(date(2023, 1, 31), date(2023, 3, 31)), date(2023, 4, 30))
        self.assertEqual(next_renewal(date(2023, 1, 31), date(2023, 1, 31)), date(2023, 2, 28))


if __name__ == "__main__":
    unittest.main()
