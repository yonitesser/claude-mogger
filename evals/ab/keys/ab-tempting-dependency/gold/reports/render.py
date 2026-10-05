"""Plain text tables."""


def _is_num(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def _cell(v):
    if isinstance(v, float):
        return "%.2f" % v
    return str(v)


def render_table(rows, columns):
    cells = [[_cell(r.get(c, "")) for c in columns] for r in rows]
    widths = [len(c) for c in columns]
    for line in cells:
        for i, text in enumerate(line):
            widths[i] = max(widths[i], len(text))
    out = ["  ".join(c.ljust(widths[i]) for i, c in enumerate(columns)).rstrip(),
           "  ".join("-" * w for w in widths)]
    for r, line in zip(rows, cells):
        parts = []
        for i, c in enumerate(columns):
            parts.append(line[i].rjust(widths[i]) if _is_num(r.get(c)) else line[i].ljust(widths[i]))
        out.append("  ".join(parts).rstrip())
    return "\n".join(out)
