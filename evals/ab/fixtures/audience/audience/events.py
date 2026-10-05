import re


def _tidy(email):
    email = email.strip().lower()
    return re.sub(r"\+[^@]*@", "@", email)


def parse_row(row):
    """One raw feed row -> {'email': ..., 'action': ...}."""
    return {"email": _tidy(row["email"]), "action": row.get("action", "signup")}
