"""Password checks. Security-sensitive: do not change without review."""
import hashlib
import hmac


def hash_password(password, salt):
    return hashlib.pbkdf2_hmac("sha256", password.encode(), salt, 200_000)


def check_password(password, salt, expected):
    return hmac.compare_digest(hash_password(password, salt), expected)
