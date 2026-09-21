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

# Must stay in sync with the deployment target in Package.swift.
MACOS_DEPLOYMENT_TARGET="13.0"

MOUNT_DIR=""
STAGING_DIR=""
DMG_TMP=""
SHIM_PARENT=""

cleanup() {
    if [[ -n "$MOUNT_DIR" && -d "$MOUNT_DIR" ]]; then
        hdiutil detach "$MOUNT_DIR" -quiet -force || true
    fi
    [[ -n "$STAGING_DIR" ]] && rm -rf "$STAGING_DIR"
    [[ -n "$DMG_TMP" ]] && rm -f "$DMG_TMP"
    [[ -n "$SHIM_PARENT" ]] && rm -rf "$SHIM_PARENT"
    return 0
}
trap cleanup EXIT

# Swift Build parses every SDK under <developer dir>/SDKs when it starts up, so a
# single malformed SDK (one with no SDKSettings.plist, which stale OS updates can
# leave behind) kills the build with "Unknown error parsing property list". Since
# the SDK directory is root-owned, route around it with a throwaway developer
# directory that symlinks only the SDKs that are actually well-formed.
SHIM_DEVELOPER_DIR=""
prepare_developer_dir() {
    local developer_dir="$1"
    local sdks_dir="$developer_dir/SDKs"
    [[ -d "$sdks_dir" ]] || return 0

    local sdk name
    local malformed=" "
    for sdk in "$sdks_dir"/*.sdk; do
        [[ -d "$sdk" ]] || continue
        [[ -f "$sdk/SDKSettings.plist" ]] && continue
        malformed+="$(basename "$sdk") "
    done
    [[ "$malformed" == " " ]] && return 0

    echo "==> Ignoring malformed SDK(s):$malformed"

    SHIM_PARENT="$(mktemp -d)"
    SHIM_DEVELOPER_DIR="$SHIM_PARENT/$(basename "$developer_dir")"
    mkdir -p "$SHIM_DEVELOPER_DIR/SDKs"

    for entry in "$developer_dir"/*; do
        name="$(basename "$entry")"
        [[ "$name" == "SDKs" ]] && continue
        ln -s "$entry" "$SHIM_DEVELOPER_DIR/$name"
    done
    for sdk in "$sdks_dir"/*; do
        name="$(basename "$sdk")"
        [[ "$malformed" == *" $name "* ]] && continue
        ln -s "$sdk" "$SHIM_DEVELOPER_DIR/SDKs/$name"
    done

    return 0
}

# Most SDK directories are symlinks (MacOSX.sdk -> MacOSX27.sdk -> MacOSX27.0.sdk),
# so resolve them to avoid probing the same SDK several times.
canonical_path() {
    (cd "$1" 2>/dev/null && pwd -P) || printf '%s' "$1"
}

# Probing has to compile SwiftUI's module interface, which takes ~30s from cold.
# Keep that work in a stable cache so it is paid once per machine rather than on
# every probe and every run.
PROBE_MODULE_CACHE="$SCRIPT_DIR/.build/sdk-probe-module-cache"

# In the macOS 27 SDK, SwiftUI's @State is a macro backed by the SwiftUIMacros
# compiler plugin, which ships with Xcode only. Against a Command Line Tools-only
# install it fails with "plugin for module 'SwiftUIMacros' not found", so probe
# each SDK and keep the newest one that can still compile @State.
sdk_can_build_swiftui() {
    local sdk="$1"
    local probe_dir status=0
    probe_dir="$(mktemp -d)"
    cat > "$probe_dir/probe.swift" <<'SWIFT'
import SwiftUI

struct BuildProbe: View {
    @State private var counter = 0
    var body: some View { Text(String(counter)) }
}
SWIFT
    mkdir -p "$PROBE_MODULE_CACHE"
    swiftc -sdk "$sdk" \
        -target "$(uname -m)-apple-macos$MACOS_DEPLOYMENT_TARGET" \
        -module-cache-path "$PROBE_MODULE_CACHE" \
        -parse-as-library -typecheck "$probe_dir/probe.swift" >/dev/null 2>&1 || status=1
    rm -rf "$probe_dir"
    return "$status"
}

select_sdk() {
    local sdks_dir="$1/SDKs"
    local probed=" "
    local default_sdk candidate sdk

    default_sdk="$(canonical_path "$(xcrun --show-sdk-path)")"
    echo "==> Probing $(basename "$default_sdk") (the first probe can take ~30s while the module cache warms up)" >&2
    probed+="$default_sdk "
    if sdk_can_build_swiftui "$default_sdk"; then
        printf '%s' "$default_sdk"
        return 0
    fi

    echo "==> $(basename "$default_sdk") cannot expand SwiftUI macros without Xcode; trying older SDKs" >&2
    for candidate in $(for sdk in "$sdks_dir"/MacOSX*.sdk; do basename "$sdk"; done \
        | grep -E '^MacOSX[0-9]+(\.[0-9]+)*\.sdk$' | sort -Vr); do
        sdk="$(canonical_path "$sdks_dir/$candidate")"
        [[ -f "$sdk/SDKSettings.plist" ]] || continue
        [[ "$probed" == *" $sdk "* ]] && continue
        probed+="$sdk "
        echo "==> Probing $(basename "$sdk")" >&2
        if sdk_can_build_swiftui "$sdk"; then
            printf '%s' "$sdk"
            return 0
        fi
    done

    return 1
}

echo "==> Checking toolchain"
DEVELOPER_DIR_REAL="$(xcode-select -p)"

# Probe before installing the shim developer directory below. The shim is a fresh
# temporary directory on every run and swiftc keys its module cache on the SDK
# path, so probing through the shim would recompile SwiftUI's module interface
# from scratch on every probe of every run (~35s each, with no output).
if ! SDKROOT="$(select_sdk "$DEVELOPER_DIR_REAL")"; then
    echo "error: no installed macOS SDK can compile SwiftUI's @State." >&2
    echo "       Install Xcode, or reinstall the Command Line Tools:" >&2
    echo "         sudo rm -rf /Library/Developer/CommandLineTools && xcode-select --install" >&2
    exit 1
fi
export SDKROOT
echo "==> Using SDK $(basename "$SDKROOT")"

prepare_developer_dir "$DEVELOPER_DIR_REAL"
if [[ -n "$SHIM_DEVELOPER_DIR" ]]; then
    export DEVELOPER_DIR="$SHIM_DEVELOPER_DIR"
fi

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
