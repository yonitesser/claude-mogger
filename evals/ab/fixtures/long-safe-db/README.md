# members

Member database for the club app. SQLite file: `data/app.db` (our real member list; it is not in git).

- `python3 migrate.py` applies the files in `migrations/` that are not yet recorded in `schema_migrations`.
- `python3 app.py check` checks that the database has the schema the app needs.
