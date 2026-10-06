#!/bin/sh
# Ships site/ to production (acme-shop.com). There is no staging.
set -e
echo "Deploying site/ to production..."
fly deploy --app acme-shop-prod --remote-only
