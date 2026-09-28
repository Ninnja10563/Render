#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP=${1:-"$(pwd)/dist/Render.app"}
FRAMEWORK=$(find .build/artifacts -type d -path '*/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework' -print -quit)
TOOLS=$(find .build/artifacts -type f -path '*/bin/generate_appcast' -print -quit)
TOOLS=$(dirname "$TOOLS")
SOURCE=$(find .build/checkouts -type f -path '*/sparkle-cli/main.m' -print -quit)
SOURCE=$(dirname "$SOURCE")
TEST_ROOT=$(mktemp -d)
ACCOUNT="render-update-test-$(uuidgen)"
SERVER_PID=""
cleanup() {
    if [ -n "$SERVER_PID" ]; then kill "$SERVER_PID" 2>/dev/null || true; fi
    security delete-generic-password -s https://sparkle-project.org -a "$ACCOUNT" >/dev/null 2>&1 || true
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT
umask 077
mkdir -p "$TEST_ROOT/server" "$TEST_ROOT/old" "$TEST_ROOT/new" build
# Compile Sparkle's own CLI against the pinned framework. This is test tooling only.
cp "$SOURCE/Info.plist" "$TEST_ROOT/probe.plist"
chmod u+w "$TEST_ROOT/probe.plist"
python3 - "$TEST_ROOT/probe.plist" <<'PY'
import plistlib,sys
p=sys.argv[1]
with open(p,'rb') as f: info=plistlib.load(f)
info.update(CFBundleIdentifier='app.render.update-probe',CFBundleName='Render Update Probe',CFBundleExecutable='probe',CFBundleVersion='1',CFBundleShortVersionString='1',LSMinimumSystemVersion='14.0')
with open(p,'wb') as f: plistlib.dump(info,f)
PY
clang -arch arm64 -mmacosx-version-min=14.0 -fobjc-arc \
    -DSPU_OBJC_DIRECT='__attribute__((objc_direct))' -DSPU_OBJC_DIRECT_MEMBERS='__attribute__((objc_direct_members))' -F "$(dirname "$FRAMEWORK")" \
    -framework Sparkle -framework Cocoa -Wl,-rpath,"$(pwd)/$(dirname "$FRAMEWORK")" \
    -Wl,-sectcreate,__TEXT,__info_plist,"$TEST_ROOT/probe.plist" \
    "$SOURCE/main.m" "$SOURCE/SPUCommandLineDriver.m" "$SOURCE/SPUCommandLineUserDriver.m" -o "$TEST_ROOT/probe"
run_probe() {
    python3 - "$TEST_ROOT/probe" "$@" <<'PYTHON'
import subprocess,sys
try:
    sys.exit(subprocess.run(sys.argv[1:],timeout=90).returncode)
except subprocess.TimeoutExpired:
    print("Update integration command timed out",file=sys.stderr); sys.exit(124)
PYTHON
}
"$TOOLS/generate_keys" --account "$ACCOUNT" > /dev/null
"$TOOLS/generate_keys" --account "$ACCOUNT" -x "$TEST_ROOT/test.key" > /dev/null
PUBLIC_KEY=$("$TOOLS/generate_keys" --account "$ACCOUNT" -p)
python3 scripts/update-test-server.py "$TEST_ROOT/server" "$TEST_ROOT/port" > "$TEST_ROOT/server.log" 2>&1 &
SERVER_PID=$!
for _ in $(seq 1 200); do
    [ -s "$TEST_ROOT/port" ] && break
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then cat "$TEST_ROOT/server.log"; exit 1; fi
    sleep 0.1
done
if [ ! -s "$TEST_ROOT/port" ]; then cat "$TEST_ROOT/server.log"; echo "Update fixture server did not start"; exit 1; fi
FEED="http://127.0.0.1:$(cat "$TEST_ROOT/port")/appcast.xml"
for version in old new; do
    ditto "$APP" "$TEST_ROOT/$version/Render.app"
    PLIST="$TEST_ROOT/$version/Render.app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier app.render.update-test" "$PLIST"
    /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $PUBLIC_KEY" "$PLIST"
    /usr/libexec/PlistBuddy -c "Set :SUFeedURL $FEED" "$PLIST"
    if [ "$version" = old ]; then NUMBER=0.0.1; else NUMBER=0.0.2; fi
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NUMBER" "$PLIST"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NUMBER" "$PLIST"
    codesign --force --deep --sign - "$TEST_ROOT/$version/Render.app"
done
swift scripts/check-update-key.swift "$TEST_ROOT/test.key" "$TEST_ROOT/new/Render.app/Contents/Info.plist"
ditto -c -k --sequesterRsrc --keepParent "$TEST_ROOT/new/Render.app" "$TEST_ROOT/server/Render.zip"
"$TOOLS/generate_appcast" --ed-key-file "$TEST_ROOT/test.key" --maximum-deltas 0 \
    --download-url-prefix "${FEED%appcast.xml}" "$TEST_ROOT/server"
"$TOOLS/sign_update" --ed-key-file "$TEST_ROOT/test.key" --verify "$TEST_ROOT/server/appcast.xml"
cp "$TEST_ROOT/server/appcast.xml" "$TEST_ROOT/feed.good"
cp "$TEST_ROOT/server/Render.zip" "$TEST_ROOT/archive.good"
# A forged feed must be rejected before any installer is offered.
python3 - "$TEST_ROOT/server/appcast.xml" <<'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1]); p.write_bytes(p.read_bytes().replace(b'<title>',b'<title>Forged ',1))
PY
if run_probe "$TEST_ROOT/old/Render.app" --probe --feed-url "$FEED" > build/update-forged-feed.log 2>&1; then
    echo "Forged update feed was accepted"; exit 1
fi
grep -iE 'signature|signed|validation' build/update-forged-feed.log
cp "$TEST_ROOT/feed.good" "$TEST_ROOT/server/appcast.xml"
# Keep the download length unchanged while invalidating its signature.
python3 - "$TEST_ROOT/server/Render.zip" <<'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1]); data=bytearray(p.read_bytes()); data[1024]^=1; p.write_bytes(data)
PY
if run_probe "$TEST_ROOT/old/Render.app" --check-immediately --feed-url "$FEED" > build/update-corrupt-download.log 2>&1; then
    echo "Corrupt update was accepted"; exit 1
fi
grep -iE 'signature|signed|validation' build/update-corrupt-download.log
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$TEST_ROOT/old/Render.app/Contents/Info.plist")" = 0.0.1
cp "$TEST_ROOT/archive.good" "$TEST_ROOT/server/Render.zip"
run_probe "$TEST_ROOT/old/Render.app" --check-immediately --feed-url "$FEED" > build/update-install.log 2>&1
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$TEST_ROOT/old/Render.app/Contents/Info.plist")" = 0.0.2
codesign --verify --deep --strict "$TEST_ROOT/old/Render.app"
set +e
run_probe "$TEST_ROOT/old/Render.app" --probe --feed-url "$FEED" > build/update-current.log 2>&1
RESULT=$?
set -e
test "$RESULT" = 4
python3 - "$TEST_ROOT/old/Render.app/Contents/MacOS/Render" "$TEST_ROOT/updated-workspace.png" <<'PYTHON'
import os,subprocess,sys
with open('build/update-launch.log','w') as log:
    result=subprocess.run([sys.argv[1],'--smoke-test'],env={**os.environ,'RENDER_APPEARANCE':'dark','RENDER_SCREENSHOT':sys.argv[2]},stdout=log,stderr=subprocess.STDOUT,timeout=90)
    sys.exit(result.returncode)
PYTHON
grep -q RENDER_SMOKE_OK build/update-launch.log
echo "RENDER_UPDATE_INSTALL_OK signed-feed forged-feed corrupt-archive install current-version launch"
