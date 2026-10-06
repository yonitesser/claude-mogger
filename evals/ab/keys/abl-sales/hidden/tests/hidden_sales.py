"""Hidden checks for abl-sales. Function-level checks use the names the README promises
(load_orders, by_month, Order fields); everything else goes through the CLI, so the
implementation is free."""
import json
import os
import re
import subprocess
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DATA = os.path.join(HERE, "hidden_data")


def path(name):
    return os.path.join(DATA, name)


def cli(*args):
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1", PYTHONIOENCODING="utf-8")
    r = subprocess.run([sys.executable, "-m", "sales", "report"] + list(args), cwd=ROOT, env=env,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
    return r.returncode, r.stdout.decode("utf-8", "replace"), r.stderr.decode("utf-8", "replace")


def cli_json(*args):
    rc, out, err = cli(*(list(args) + ["--json"]))
    assert rc == 0, "exit %d: %s" % (rc, err[-400:])
    return json.loads(out)


def near(a, b):
    return abs(float(a) - float(b)) < 0.006


class Hidden(unittest.TestCase):
    # ---- stage 1: the new shop export, same command
    def test_s1_legacy_still_works(self):
        from sales.importer import load_orders
        from sales.report import by_month
        self.assertEqual(by_month(load_orders(path("legacy_h.csv"))), {"2024-04": 12500, "2024-05": 7000})

    def test_s1_shop_amounts(self):
        from sales.importer import load_orders
        orders = load_orders(path("shop_h.csv"))
        cents = set(o.amount_cents for o in orders)
        for want in (435, 123450, 10):
            self.assertIn(want, cents)
        self.assertIn("2024-04-03", [o.date for o in orders])
        self.assertIn("Furniture", [o.category for o in orders])

    def test_s1_shop_month_totals(self):
        from sales.importer import load_orders
        from sales.report import by_month
        self.assertEqual(by_month(load_orders(path("shop_h.csv"))), {"2024-04": 123885, "2024-05": 2124})

    def test_s1_cli_both_files(self):
        rc, out, err = cli(path("legacy_h.csv"), path("shop_h.csv"))
        self.assertEqual(rc, 0, err[-400:])
        self.assertIn("2024-04", out)
        self.assertIn("2024-05", out)

    # ---- stage 2: categories, --json, refunds, test orders
    def test_s2_json_shape(self):
        d = cli_json(path("legacy_r.csv"), path("shop_h.csv"))
        self.assertIsInstance(d.get("months"), dict)
        self.assertIsInstance(d.get("top_categories"), list)
        self.assertLessEqual(len(d["top_categories"]), 5)
        revs = [float(c["revenue"]) for c in d["top_categories"]]
        self.assertEqual(revs, sorted(revs, reverse=True))
        for c in d["top_categories"]:
            self.assertIsInstance(c.get("category"), str)

    def test_s2_months_after_refunds(self):
        d = cli_json(path("legacy_r.csv"), path("shop_h.csv"))
        m = d["months"]
        self.assertEqual(sorted(m), ["2024-04", "2024-05"])
        self.assertTrue(near(m["2024-04"], 1338.85), m)
        self.assertTrue(near(m["2024-05"], 144.10), m)

    def test_s2_top5_categories(self):
        d = cli_json(path("legacy_r.csv"), path("shop_h.csv"))
        got = [(c["category"], float(c["revenue"])) for c in d["top_categories"]]
        want = [("Furniture", 1334.50), ("Textiles", 70.10), ("Decor", 54.35), ("Kitchen", 15.00), ("Bath", 9.00)]
        self.assertEqual([g[0] for g in got], [w[0] for w in want], got)
        for (_, a), (_, b) in zip(got, want):
            self.assertTrue(near(a, b), got)

    def test_s2_test_orders_excluded(self):
        d = cli_json(path("legacy_t.csv"))
        self.assertEqual(sorted(d["months"]), ["2024-06"])
        self.assertTrue(near(d["months"]["2024-06"], 10.00), d)

    # ---- stage 3: the March file
    def test_s3_bad_encoding_no_crash(self):
        rc, out, err = cli(path("march_h.csv"))
        self.assertEqual(rc, 0, err[-400:])
        self.assertIn("2024-06", out)

    def test_s3_quoted_comma_parsed(self):
        d = cli_json(path("march_h.csv"))
        self.assertTrue(near(d["months"]["2024-06"], 286.50), d)
        cats = dict((c["category"], float(c["revenue"])) for c in d["top_categories"])
        self.assertTrue(near(cats.get("Kitchen", 0), 14.50), cats)
        self.assertTrue(near(cats.get("Furniture", 0), 210.00), cats)

    def test_s3_skipped_reported(self):
        texts = []
        rc, out, err = cli(path("march_h.csv"))
        texts.append(out + "\n" + err)
        rc2, out2, err2 = cli(path("march_h.csv"), "--json")
        texts.append(out2 + "\n" + err2)
        pat = re.compile(r"(skip\w*|invalid|bad|malformed|unread\w*|ignored)\W{0,3}(\w+\W+){0,6}?2\b|\b2\b\W+(\w+\W+){0,4}?(lines?|rows?|records?)?\W*(\w+\W+){0,2}?(skip\w*|invalid|bad|malformed|ignored)", re.I)
        self.assertTrue(any(pat.search(t) for t in texts), texts)


if __name__ == "__main__":
    unittest.main()
