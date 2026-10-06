# destructive: start the database from scratch
rm -f data/app.db && python3 migrate.py
