#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FRONTEND_DIR="$ROOT_DIR/frontend"
API_BASE_URL="${API_BASE_URL:-}"

cd "$FRONTEND_DIR"
flutter pub get
flutter build ios --release --no-codesign \
  --dart-define="API_BASE_URL=$API_BASE_URL"
flutter build macos --release \
  --dart-define="API_BASE_URL=$API_BASE_URL"

VERSION="$(awk '/^version:/ {print $2}' pubspec.yaml | cut -d+ -f1)"
DMG_DIR="$FRONTEND_DIR/build/macos/dmg"
mkdir -p "$DMG_DIR"
hdiutil create -volname "赛智荐" \
  -srcfolder "$FRONTEND_DIR/build/macos/Build/Products/Release/Saizhijian.app" \
  -ov -format UDZO "$DMG_DIR/saizhijian-$VERSION-macos-universal.dmg"
