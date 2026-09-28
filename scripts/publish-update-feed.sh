#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(tr -d '\n' < VERSION)
test -s dist/update/appcast.xml
# Only publish the feed after the versioned release asset is publicly available.
gh release view "v$VERSION" --json assets --jq '.assets[].name' | grep -Fx "Render-$VERSION-Apple-Silicon.dmg"
STAGE=$(mktemp -d)
cleanup() { git worktree remove --force "$STAGE" >/dev/null 2>&1 || true; }
trap cleanup EXIT
if git ls-remote --exit-code --heads origin updates >/dev/null; then
    git fetch origin updates
    git worktree add --detach "$STAGE" FETCH_HEAD
else
    git worktree add --detach "$STAGE" HEAD
    git -C "$STAGE" switch --orphan "update-feed-${GITHUB_RUN_ID:-local}"
fi
cp dist/update/appcast.xml "$STAGE/appcast.xml"
git -C "$STAGE" add appcast.xml
git -C "$STAGE" -c user.name='Render Releases' -c user.email='41898282+github-actions[bot]@users.noreply.github.com' commit -m "release: publish signed update feed for $VERSION"
git -C "$STAGE" push origin HEAD:refs/heads/updates
