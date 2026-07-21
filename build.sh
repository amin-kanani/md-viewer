#!/bin/bash
# Builds MDViewer and packages it as a double-clickable MD Viewer.app.
set -euo pipefail

APP_TARGET="MDViewer"
APP_DISPLAY_NAME="MD Viewer"
BUILD_CONFIG="release"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "==> Building $APP_TARGET ($BUILD_CONFIG)…"
swift build -c "$BUILD_CONFIG"
BIN_DIR="$(swift build -c "$BUILD_CONFIG" --show-bin-path)"

APP_BUNDLE="$SCRIPT_DIR/$APP_DISPLAY_NAME.app"
echo "==> Packaging $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$BIN_DIR/$APP_TARGET" "$APP_BUNDLE/Contents/MacOS/$APP_TARGET"
cp "$SCRIPT_DIR/AppResources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$SCRIPT_DIR/AppResources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

echo "==> Ad-hoc code signing"
codesign --force --deep --sign - "$APP_BUNDLE"

echo "==> Registering document types with Launch Services"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_BUNDLE"

echo "==> Done: $APP_BUNDLE"
echo "Run with: open \"$APP_BUNDLE\""
