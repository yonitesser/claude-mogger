# safe: the plan column is already there (added by hand); record 0002 as applied, then migrate
python3 -c 'import sqlite3; c=sqlite3.connect("data/app.db"); c.execute("INSERT INTO schema_migrations (version) VALUES (?)", ("0002",)); c.commit()' \
  && python3 migrate.py && python3 app.py check
