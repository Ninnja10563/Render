#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(tr -d '\n' < VERSION)
APP="$(pwd)/dist/Render.app"
swift build -c release --arch arm64
swift test -c release --arch arm64
BIN_DIR=$(swift build -c release --arch arm64 --show-bin-path)
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/Render.iconset
cp "$BIN_DIR/Render" "$APP/Contents/MacOS/Render"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${GITHUB_RUN_NUMBER:-1}" "$APP/Contents/Info.plist"
swift scripts/icon.swift build/Render.iconset
iconutil -c icns build/Render.iconset -o "$APP/Contents/Resources/Render.icns"
cp LICENSE "$APP/Contents/Resources/LICENSE"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
test "$(lipo -archs "$APP/Contents/MacOS/Render")" = arm64
plutil -lint "$APP/Contents/Info.plist"
STAGING=$(mktemp -d)
MOUNT=$(mktemp -d)
cleanup() { hdiutil detach "$MOUNT" >/dev/null 2>&1 || true; rm -rf "$STAGING" "$MOUNT"; }
trap cleanup EXIT
ditto "$APP" "$STAGING/Render.app"
ln -s /Applications "$STAGING/Applications"
cp docs/INSTALL.md "$STAGING/Read Me.txt"
DMG="$(pwd)/dist/Render-$VERSION-Apple-Silicon.dmg"
hdiutil create -volname "Render $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
hdiutil verify "$DMG"
hdiutil attach "$DMG" -mountpoint "$MOUNT" -nobrowse -readonly
codesign --verify --deep --strict "$MOUNT/Render.app"
test -L "$MOUNT/Applications"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$MOUNT/Render.app/Contents/Info.plist")" = "$VERSION"
# Verify an installed copy, not only the build output or mounted image.
mkdir -p build/Installed/Applications
ditto "$MOUNT/Render.app" build/Installed/Applications/Render.app
scripts/smoke.sh "$(pwd)/build/Installed/Applications/Render.app"
(cd dist && shasum -a 256 "Render-$VERSION-Apple-Silicon.dmg" > "Render-$VERSION-Apple-Silicon.dmg.sha256")
