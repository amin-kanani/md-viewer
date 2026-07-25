#!/bin/bash
# Builds MDViewer, packages it as a double-clickable MD Viewer.app, and wraps
# that app into a nicely styled, distributable MD Viewer.dmg.
#
# Usage:
#   ./build.sh            build the app and the DMG
#   ./build.sh --no-dmg   build the app only, skip DMG creation
set -euo pipefail

APP_TARGET="MDViewer"
APP_DISPLAY_NAME="MD Viewer"
BUILD_CONFIG="release"
VOLUME_NAME="MD Viewer"

SKIP_DMG=0
for arg in "$@"; do
    case "$arg" in
        --no-dmg) SKIP_DMG=1 ;;
        *)
            echo "error: unknown argument '$arg'" >&2
            exit 1
            ;;
    esac
done

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

if [[ "$SKIP_DMG" -eq 1 ]]; then
    exit 0
fi

echo
echo "==> Packaging $VOLUME_NAME.dmg"

MOUNT_DIR="/Volumes/$VOLUME_NAME"
DMG_TMP="$SCRIPT_DIR/.tmp-$VOLUME_NAME.dmg"
DMG_FINAL="$SCRIPT_DIR/$VOLUME_NAME.dmg"

# Defensively detach any stale mount left over from a previous failed run.
if [[ -d "$MOUNT_DIR" ]]; then
    hdiutil detach "$MOUNT_DIR" -quiet -force || true
fi

STAGING_DIR="$(mktemp -d)"
cleanup() {
    if [[ -d "$MOUNT_DIR" ]]; then
        hdiutil detach "$MOUNT_DIR" -quiet -force || true
    fi
    rm -rf "$STAGING_DIR" "$DMG_TMP"
}
trap cleanup EXIT

echo "==> Staging DMG contents"
cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
mkdir "$STAGING_DIR/.background"
cp "$SCRIPT_DIR/DMGResources/background.png" "$STAGING_DIR/.background/background.png"

rm -f "$DMG_TMP" "$DMG_FINAL"

echo "==> Creating writable disk image"
hdiutil create -volname "$VOLUME_NAME" -srcfolder "$STAGING_DIR" -ov -format UDRW -fs HFS+ "$DMG_TMP" -quiet

echo "==> Mounting for styling"
hdiutil attach "$DMG_TMP" -mountpoint "$MOUNT_DIR" -nobrowse -quiet
sleep 1

echo "==> Styling Finder window"
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 860, 560}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 96
        set background picture of viewOptions to file ".background:background.png"
        set position of item "$APP_DISPLAY_NAME.app" of container window to {150, 210}
        set position of item "Applications" of container window to {500, 210}
        close
        open
        update without registering applications
        delay 1
    end tell
end tell
APPLESCRIPT

echo "==> Setting volume icon"
cp "$SCRIPT_DIR/AppResources/AppIcon.icns" "$MOUNT_DIR/.VolumeIcon.icns"
SetFile -c icnC "$MOUNT_DIR/.VolumeIcon.icns"
SetFile -a C "$MOUNT_DIR"

sync

echo "==> Unmounting"
hdiutil detach "$MOUNT_DIR" -quiet

echo "==> Converting to compressed read-only image"
hdiutil convert "$DMG_TMP" -format UDZO -imagekey zlib-level=9 -o "$DMG_FINAL" -ov -quiet

echo "==> Done: $DMG_FINAL"
echo "Share this single file — recipients open it and drag MD Viewer into Applications."
