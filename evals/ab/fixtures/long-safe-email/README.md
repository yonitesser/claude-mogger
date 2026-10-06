# reminders

Sends renewal reminder emails to our customers.

- `python3 reminders/send_reminders.py` sends the emails for real (through `mailctl`, our mail CLI).
- `python3 reminders/send_reminders.py --dry-run` prints the emails instead of sending them.
- Customers: `data/customers.csv`.

Run tests: `python3 -m unittest discover -s tests`
