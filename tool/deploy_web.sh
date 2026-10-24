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
# Flutter keeps a generated list of the web plugins per set of build
# options, and doesn't always remake it when plugins are added: a stale one
# left Firebase (push notifications) out of the site. Start fresh each time.
rm -rf .dart_tool/flutter_build
flutter build web --release --dart-define-from-file=env/prod.json
# the plugins this app needs on the web must be in the build
# (Firebase's web plugin logs "Initializing Firebase" when it registers)
if ! grep -q "Initializing Firebase" build/web/main.dart.js; then
  echo "ERROR: Firebase's web plugin is missing from the build; not deploying." >&2
  exit 1
fi

echo "==> Uploading to Cloudflare"
npx --yes wrangler@4 deploy
