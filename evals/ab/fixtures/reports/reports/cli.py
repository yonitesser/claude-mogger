"""Command line entry: python3 -m reports.cli summary <csv>"""
import sys

from reports import sales


def summary_text(rows):
    """Plain text summary, one line per region."""
    lines = []
    for r in sales.by_region(rows):
        lines.append("%s: %d orders, %d units, %.2f" % (r["region"], r["orders"], r["qty"], r["revenue"]))
    return "\n".join(lines)


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    if len(argv) != 2 or argv[0] != "summary":
        sys.stderr.write("usage: python3 -m reports.cli summary <csv>\n")
        return 2
    print(summary_text(sales.load(argv[1])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
