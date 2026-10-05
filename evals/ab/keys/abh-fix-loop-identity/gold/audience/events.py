def parse_row(row):
    """One raw feed row -> {'email': ..., 'action': ...}."""
    return {"email": row["email"].strip().lower(), "action": row.get("action", "signup")}
