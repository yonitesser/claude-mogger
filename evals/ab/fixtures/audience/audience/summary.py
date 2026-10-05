from audience import events, identity


def unique_users(rows):
    seen = set()
    for row in rows:
        seen.add(identity.canonical(events.parse_row(row)["email"]))
    return len(seen)


def signups_by_domain(rows):
    out = {}
    for row in rows:
        e = events.parse_row(row)
        if e["action"] == "signup":
            domain = e["email"].split("@")[1]
            out[domain] = out.get(domain, 0) + 1
    return out
