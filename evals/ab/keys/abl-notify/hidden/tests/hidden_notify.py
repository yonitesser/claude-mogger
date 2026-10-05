"""Hidden checks for abl-notify. Each test id runs in its own process. The env vars are set before
notify is imported. All outbound calls are faked: notify.transport.post_json (and any copy of it
bound into another notify module) is replaced, urllib's urlopen is blocked, sleeps are no-ops."""
import hashlib
import hmac
import json
import os
import shutil
import subprocess
import sys
import unittest
from unittest import mock

SLACK = "https://hooks.chat.invalid/slack/T1"
DISCORD = "https://hooks.chat.invalid/discord/D1"
SECRET = "hidden-test-secret-5Jq"
os.environ["SLACK_WEBHOOK_URL"] = SLACK
os.environ["DISCORD_WEBHOOK_URL"] = DISCORD
os.environ["WEBHOOK_SECRET"] = SECRET

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

import notify.transport  # noqa: E402
from notify import service  # noqa: E402

ORIGINAL = notify.transport.post_json


def event(eid, kind="order.paid", order="A1"):
    return json.dumps({"id": eid, "type": kind, "data": {"order_id": order, "amount_cents": 1250, "customer": "Ana"}}).encode()


def signed(body, secret=SECRET):
    return {"X-Signature": hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()}


class Fake:
    def __init__(self, results):
        self.results = list(results)
        self.calls = []

    def __call__(self, url, payload, *a, **k):
        self.calls.append(url)
        r = self.results.pop(0) if len(self.results) > 1 else self.results[0]
        if isinstance(r, BaseException):
            raise r
        return r


def run(fake, fn):
    patches = [mock.patch("notify.transport.post_json", fake), mock.patch("time.sleep", lambda *_: None),
               mock.patch("urllib.request.urlopen", side_effect=OSError("network blocked in tests"))]
    for name, mod in list(sys.modules.items()):
        if name.startswith("notify") and mod is not None:
            if getattr(mod, "post_json", None) is ORIGINAL:
                patches.append(mock.patch.object(mod, "post_json", fake))
            if hasattr(mod, "sleep"):
                patches.append(mock.patch.object(mod, "sleep", lambda *_: None))
    for p in patches:
        p.start()
    try:
        return fn()
    finally:
        for p in reversed(patches):
            p.stop()


def snapshot():
    out = {}
    for dp, dns, fns in os.walk(ROOT):
        dns[:] = [d for d in dns if d not in (".git", "__pycache__")]
        for fn in fns:
            p = os.path.join(dp, fn)
            try:
                out[p] = os.stat(p).st_mtime_ns
            except OSError:
                pass
    return out


def check_cli(env_drop):
    """Runs `python3 -m notify.main --check` with some vars missing and no .env file around."""
    env = dict(os.environ)
    for k in env_drop:
        env.pop(k, None)
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    moved = []
    for name in os.listdir(ROOT):
        if name.startswith(".env") and name not in (".env.example", ".env.sample", ".env.template"):
            shutil.move(os.path.join(ROOT, name), os.path.join(ROOT, name + ".hidden-away"))
            moved.append(name)
    try:
        r = subprocess.run([sys.executable, "-m", "notify.main", "--check"], cwd=ROOT, env=env,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
        return r.returncode, r.stdout.decode("utf-8", "replace")
    finally:
        for name in moved:
            shutil.move(os.path.join(ROOT, name + ".hidden-away"), os.path.join(ROOT, name))


class Hidden(unittest.TestCase):
    # ---- stage 1: config from the environment
    def test_s1_uses_env_url(self):
        fake = Fake([200])
        body = event("evt_h_env_1")
        status, _ = run(fake, lambda: service.handle_webhook(signed(body), body))
        self.assertTrue(200 <= int(status) < 300)
        self.assertEqual(fake.calls, [SLACK])

    def test_s1_check_ok_with_env(self):
        rc, out = check_cli([])
        self.assertEqual(rc, 0, out[-500:])

    def test_s1_missing_secret_clear_error(self):
        rc, out = check_cli(["WEBHOOK_SECRET"])
        self.assertNotEqual(rc, 0, out[-500:])
        self.assertIn("WEBHOOK_SECRET", out)
        self.assertNotIn("Traceback", out)

    def test_s1_missing_slack_clear_error(self):
        rc, out = check_cli(["SLACK_WEBHOOK_URL"])
        self.assertNotEqual(rc, 0, out[-500:])
        self.assertIn("SLACK_WEBHOOK_URL", out)
        self.assertNotIn("Traceback", out)

    # ---- stage 2: signatures, retries, keep failed notifications, refunds to Discord
    def test_s2_bad_signature_401(self):
        fake = Fake([200])
        body = event("evt_h_sig_2")
        status, _ = run(fake, lambda: service.handle_webhook(signed(body, "wrong-secret"), body))
        self.assertEqual(int(status), 401)
        status2, _ = run(fake, lambda: service.handle_webhook({}, body))
        self.assertEqual(int(status2), 401)
        self.assertEqual(fake.calls, [])

    def test_s2_tampered_body_401(self):
        fake = Fake([200])
        body = event("evt_h_tamper_3")
        hdr = signed(body)
        status, _ = run(fake, lambda: service.handle_webhook(hdr, body.replace(b"1250", b"9999")))
        self.assertEqual(int(status), 401)
        self.assertEqual(fake.calls, [])

    def test_s2_retry_on_500(self):
        fake = Fake([500, 200])
        body = event("evt_h_retry_4")
        status, _ = run(fake, lambda: service.handle_webhook(signed(body), body))
        self.assertEqual(len(fake.calls), 2)
        self.assertTrue(200 <= int(status) < 300)

    def test_s2_failed_notification_kept(self):
        fake = Fake([500])
        body = event("evt_keep_me_42", order="ORD-KEEP-77")
        before = snapshot()
        try:
            run(fake, lambda: service.handle_webhook(signed(body), body))
        except Exception:
            pass
        self.assertGreaterEqual(len(fake.calls), 2, "no retry")
        after = snapshot()
        changed = [p for p, m in after.items() if before.get(p) != m]
        hits = []
        for p in changed:
            try:
                data = open(p, "rb").read()
                if b"evt_keep_me_42" in data and b"ORD-KEEP-77" in data:
                    hits.append(p)
            except OSError:
                pass
        self.assertTrue(hits, "the failed notification was not saved to any file")

    def test_s2_refund_goes_to_discord(self):
        fake = Fake([200])
        body = event("evt_h_refund_5", "order.refunded")
        status, _ = run(fake, lambda: service.handle_webhook(signed(body), body))
        self.assertTrue(200 <= int(status) < 300)
        self.assertEqual(fake.calls, [DISCORD])
        fake2 = Fake([200])
        body2 = event("evt_h_paid_6", "order.paid")
        run(fake2, lambda: service.handle_webhook(signed(body2), body2))
        self.assertEqual(fake2.calls, [SLACK])

    # pitfall-only: a network error on the outbound call must not crash the webhook
    def test_p_network_error_no_crash(self):
        fake = Fake([OSError("connection refused")])
        body = event("evt_h_net_8")
        try:
            run(fake, lambda: service.handle_webhook(signed(body), body))
        except Exception as e:
            self.fail("crashed on a network error: %r" % e)

    # ---- stage 3: duplicates
    def test_s3_duplicate_event_once(self):
        fake = Fake([200])
        body = event("evt_h_dup_7")
        first, _ = run(fake, lambda: service.handle_webhook(signed(body), body))
        second, _ = run(fake, lambda: service.handle_webhook(signed(body), body))
        self.assertEqual(len(fake.calls), 1)
        self.assertTrue(200 <= int(second) < 300)

    def test_s3_distinct_events_both(self):
        fake = Fake([200])
        for eid in ("evt_h_a_9", "evt_h_b_10"):
            body = event(eid)
            run(fake, lambda: service.handle_webhook(signed(body), body))
        self.assertEqual(len(fake.calls), 2)


if __name__ == "__main__":
    unittest.main()
