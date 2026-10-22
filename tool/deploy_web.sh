#!/usr/bin/env bash
# Builds the web app against the production backend (env/prod.json) and
# uploads build/web to Cloudflare (wrangler.jsonc). Run from Git Bash:
#
#   tool/deploy_web.sh
#
# First time only: npx wrangler@4 login
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> Building web app (production backend)"
flutter build web --release --dart-define-from-file=env/prod.json

echo "==> Uploading to Cloudflare"
npx --yes wrangler@4 deploy
