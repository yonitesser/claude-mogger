#!/usr/bin/env bash
# Copies the real secret guard into teaser/ so the free copy never drifts.
# lib.sh in teaser/ is a hand-trimmed copy: check it when hooks/scripts/lib.sh changes.
set -e
cd "$(dirname "$0")/.."
cp hooks/scripts/secret-guard.sh hooks/scripts/secret-patterns.sh teaser/hooks/scripts/
echo "teaser/ synced"
