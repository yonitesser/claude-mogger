#!/usr/bin/env bash
# Thin wrapper so this matches the rest of scripts/ — the real logic is
# Python (cleaner for the arithmetic/JSON than bash).
exec python3 "$(dirname "$0")/savings-report.py" "$@"
