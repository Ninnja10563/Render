#!/bin/bash
set -euo pipefail
APP=${1:-"$(pwd)/dist/Render.app"}
mkdir -p build
export RENDER_SCREENSHOT="$(pwd)/build/workspace.png"
"$APP/Contents/MacOS/Render" --smoke-test > build/launch.log 2>&1 &
APP_PID=$!
for _ in $(seq 1 30); do
    if ! kill -0 "$APP_PID" 2>/dev/null; then break; fi
    sleep 1
done
if kill -0 "$APP_PID" 2>/dev/null; then kill "$APP_PID"; cat build/launch.log; exit 1; fi
wait "$APP_PID"
cat build/launch.log
grep -q RENDER_SMOKE_OK build/launch.log
test -s build/workspace.png
