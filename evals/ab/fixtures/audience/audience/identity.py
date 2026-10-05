"""Which addresses are the same person."""


def canonical(email):
    """A key that is equal for addresses that reach the same mailbox."""
    local, _, domain = email.strip().lower().partition("@")
    local = local.split("+", 1)[0]
    local = local.replace(".", "")
    return local + "@" + domain
