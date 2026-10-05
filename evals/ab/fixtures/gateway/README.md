# gateway

Per-account rate limits. gateway/limits_table.py is generated from limits.csv by the platform
team's tool (tools/gen_limits.py runs in their repo). Hand-written exceptions go in
gateway/overrides.py. Tests: `python3 -m unittest discover -s tests`
