# 

#!/usr/bin/env bash
set -euo pipefail

APP_NAME="secondstudent"

echo "→ Stopping any running $APP_NAME app (ignore errors if not running)…"
pkill -f "$APP_NAME" || true

echo "→ flutter clean"
flutter clean

echo "→ Removing build/macos"
rm -rf build/macos

echo "→ Stripping extended attributes (xattr) from sources…"
xattr -rc macos
xattr -rc assets || true
xattr -rc lib || true

echo "→ Stripping xattrs from any previously built app bundle (if present)…"
xattr -rc "build/macos/Build/Products/Debug/${APP_NAME}.app" 2>/dev/null || true

echo "→ Running on macOS…"
flutter run -d macos
