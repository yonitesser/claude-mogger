"""Which addresses are the same person."""

GMAIL = ("gmail.com", "googlemail.com")


def canonical(email):
    """A key that is equal for addresses that reach the same mailbox.
    Only Gmail ignores dots and +tags in the local part; elsewhere they are significant."""
    local, _, domain = email.strip().lower().partition("@")
    if domain in GMAIL:
        local = local.split("+", 1)[0].replace(".", "")
        domain = "gmail.com"
    return local + "@" + domain
