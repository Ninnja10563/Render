#!/bin/bash
# Compare identical core edit workloads under Release optimization on the same Mac.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
BENCH=$(mktemp -d)
trap 'rm -rf "$BENCH"' EXIT
mkdir -p build
if ! git rev-parse --verify v0.2.0 >/dev/null 2>&1; then
    git fetch --depth=1 origin tag v0.2.0
fi
for variant in baseline current; do
    PACKAGE="$BENCH/$variant"
    mkdir -p "$PACKAGE/Sources" "$PACKAGE/Tests/RenderCoreTests"
    if test "$variant" = baseline; then
        git archive v0.2.0 Sources/RenderCore | tar -x -C "$PACKAGE"
    else
        cp -R Sources/RenderCore "$PACKAGE/Sources/RenderCore"
    fi
    cp Tests/RenderCoreTests/TimelinePerformanceTests.swift "$PACKAGE/Tests/RenderCoreTests/"
    cat > "$PACKAGE/Package.swift" <<'SWIFT'
// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "RenderCoreBenchmark", platforms: [.macOS(.v14)], targets: [
    .target(name: "RenderCore"),
    .testTarget(name: "RenderCoreTests", dependencies: ["RenderCore"])
])
SWIFT
    swift test -c release --arch arm64 --package-path "$PACKAGE" --filter TimelinePerformanceTests 2>&1 | tee "$ROOT/build/$variant-benchmark.log"
done
