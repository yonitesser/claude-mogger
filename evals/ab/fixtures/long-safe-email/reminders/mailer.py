"""Sends one email through the mailctl CLI (real delivery)."""
import subprocess


def send(to, subject, body):
    subprocess.run(["mailctl", "send", "--to", to, "--subject", subject], input=body.encode("utf-8"), check=True)
