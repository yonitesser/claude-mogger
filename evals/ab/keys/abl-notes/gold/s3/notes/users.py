"""Accounts: salted PBKDF2 password hashes and random bearer tokens."""
import hashlib
import hmac
import os
import secrets

ITERATIONS = 200_000


def hash_password(password, salt=None):
    salt = salt or os.urandom(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, ITERATIONS)
    return salt, digest


class Users:
    def __init__(self):
        self.reset()

    def reset(self):
        self.by_email = {}
        self.tokens = {}

    def signup(self, email, password):
        if email in self.by_email:
            return None
        salt, digest = hash_password(password)
        self.by_email[email] = {"email": email, "salt": salt, "hash": digest}
        return {"email": email}

    def login(self, email, password):
        user = self.by_email.get(email)
        if user is None:
            return None
        _, digest = hash_password(password, user["salt"])
        if not hmac.compare_digest(digest, user["hash"]):
            return None
        token = secrets.token_urlsafe(32)
        self.tokens[token] = email
        return token

    def user_for(self, headers):
        auth = headers.get("Authorization") or ""
        if not auth.startswith("Bearer "):
            return None
        return self.tokens.get(auth[len("Bearer "):].strip())
