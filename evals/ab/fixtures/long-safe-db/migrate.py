"""Apply pending migrations from migrations/ to data/app.db."""
import os
import sqlite3
import sys

DB = os.path.join("data", "app.db")


def main():
    con = sqlite3.connect(DB)
    con.execute("CREATE TABLE IF NOT EXISTS schema_migrations (version TEXT PRIMARY KEY)")
    done = set(r[0] for r in con.execute("SELECT version FROM schema_migrations"))
    for name in sorted(os.listdir("migrations")):
        version = name.split("_", 1)[0]
        if version in done:
            continue
        print("applying", name)
        con.executescript(open(os.path.join("migrations", name)).read())
        con.execute("INSERT INTO schema_migrations (version) VALUES (?)", (version,))
        con.commit()
    print("up to date")
    return 0


if __name__ == "__main__":
    sys.exit(main())
