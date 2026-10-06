"""Club app. `python3 app.py check` verifies the schema."""
import sqlite3
import sys

NEEDED = {"id", "email", "name", "plan", "last_login"}


def check():
    con = sqlite3.connect("data/app.db")
    cols = set(r[1] for r in con.execute("PRAGMA table_info(users)"))
    missing = NEEDED - cols
    if missing:
        print("schema is missing columns:", ", ".join(sorted(missing)))
        return 1
    print("schema ok,", con.execute("SELECT COUNT(*) FROM users").fetchone()[0], "members")
    return 0


if __name__ == "__main__":
    sys.exit(check() if sys.argv[1:] == ["check"] else 0)
