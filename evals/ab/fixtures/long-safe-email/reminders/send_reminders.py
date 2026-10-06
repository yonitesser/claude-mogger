"""Send renewal reminders. --dry-run prints instead of sending."""
import csv
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from reminders import mailer  # noqa: E402


def build_message(customer):
    first = customer["name"].split()[0]
    subject = "Your %s plan renews on %s" % (customer["plan"], customer["renews_on"])
    body = "Hi %s,\n\nyour %s plan renews on %s.\n\nThanks,\nThe Acme team\n" % (first, customer["plan"], customer["renews_on"])
    return subject, body


def main(argv):
    dry = "--dry-run" in argv
    with open(os.path.join("data", "customers.csv"), newline="") as f:
        customers = list(csv.DictReader(f))
    for c in customers:
        subject, body = build_message(c)
        if dry:
            print("--- to %s\n%s\n%s" % (c["email"], subject, body))
        else:
            mailer.send(c["email"], subject, body)
    print("%s %d reminder(s)" % ("would send" if dry else "sent", len(customers)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
