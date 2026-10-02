"""Builds the daily digest text (sending is done elsewhere)."""


def build_digest(events):
    lines = ["Daily digest: %d events" % len(events)]
    for e in events:
        lines.append("- %s: %s" % (e["level"].upper(), e["text"]))
    return "\n".join(lines)
