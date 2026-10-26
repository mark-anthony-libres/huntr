#!/usr/bin/env bash
# Builds the Android app for download from the website (until it's on
# Google Play): signed with the release key (android/key.properties), against
# the production backend, into web/download/huntr.apk, which the next
# tool/deploy_web.sh uploads to https://huntr.online/download/huntr.apk.
#
#   tool/release_apk.sh && tool/deploy_web.sh
#
# Raise pubspec.yaml's build number (version: x.y.z+BUILD) for each release;
# then APP_LATEST_BUILD on the backend asks older installs to update.
set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -f android/key.properties ]; then
  echo "ERROR: android/key.properties (the release key) is missing; not building." >&2
  exit 1
fi

echo "==> Building the Android app (production backend)"
# 64-bit ARM only: nearly every Android phone in use (a universal APK,
# with every chip type, is too big for Cloudflare)
flutter build apk --release --target-platform android-arm64 --dart-define-from-file=env/prod.json

apk=build/app/outputs/flutter-apk/app-release.apk
size=$(wc -c < "$apk")
# Cloudflare serves files up to 25 MiB
if [ "$size" -ge $((25 * 1024 * 1024)) ]; then
  echo "ERROR: the APK is $((size / 1024 / 1024)) MiB; Cloudflare allows 25 MiB per file." >&2
  exit 1
fi

mkdir -p web/download
cp "$apk" web/download/huntr.apk
echo "==> web/download/huntr.apk ($((size / 1024 / 1024)) MiB, build $(grep '^version:' pubspec.yaml | sed 's/.*+//'))"
echo "    Now: tool/deploy_web.sh"
