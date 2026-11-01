#!/usr/bin/env bash
# The free teaser/ must hold the same secret guard as the plugin, and pass its own test.
cd "$(dirname "$0")/.." || exit 1
fail=0
for f in secret-guard.sh secret-patterns.sh; do
  if diff -q "hooks/scripts/$f" "teaser/hooks/scripts/$f" >/dev/null; then echo "ok   teaser/$f matches plugin"; else echo "FAIL teaser/$f drifted: run bash scripts/sync-teaser.sh"; fail=1; fi
done
bash teaser/test.sh || fail=1
exit $fail
