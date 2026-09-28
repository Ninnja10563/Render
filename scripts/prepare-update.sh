#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SPARKLE_PRIVATE_KEY:?Missing update signing key}"
VERSION=$(tr -d '\n' < VERSION)
TOOLS=$(find .build/artifacts -type f -path '*/bin/generate_appcast' -print -quit)
TOOLS=$(dirname "$TOOLS")
KEY_FILE=$(mktemp)
trap 'rm -f "$KEY_FILE"' EXIT
chmod 600 "$KEY_FILE"
printf '%s' "$SPARKLE_PRIVATE_KEY" > "$KEY_FILE"
unset SPARKLE_PRIVATE_KEY
swift scripts/check-update-key.swift "$KEY_FILE" dist/Render.app/Contents/Info.plist
mkdir -p dist/update
DMG="Render-$VERSION-Apple-Silicon.dmg"
cp "dist/$DMG" "dist/update/$DMG"
cp "docs/releases/$VERSION.md" "dist/update/${DMG%.dmg}.md"
"$TOOLS/generate_appcast" --ed-key-file "$KEY_FILE" --maximum-deltas 0 --maximum-versions 1 \
    --download-url-prefix "https://github.com/Ninnja10563/Render/releases/download/v$VERSION/" \
    --release-notes-url-prefix "https://github.com/Ninnja10563/Render/releases/download/v$VERSION/" \
    --embed-release-notes --link "https://github.com/Ninnja10563/Render/releases/tag/v$VERSION" dist/update
"$TOOLS/sign_update" --ed-key-file "$KEY_FILE" --verify dist/update/appcast.xml
