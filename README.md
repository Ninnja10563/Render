# Render

A native, non-destructive macOS video editor built with SwiftUI, AppKit, AVFoundation and a Metal-backed Core Image compositor. Render is an early-stage long-term editor project, not yet a production replacement for an established NLE.

## Requirements

Apple Silicon · macOS 14+ · Xcode 15+ for source builds. No external runtime packages.

## Working editing path

1. Import video, audio or still images (⌘I or Finder drop).
2. Double-click media to append, or drag it onto a compatible timeline track.
3. Scrub the ruler, play with Space, select with A, blade with B, split with ⌘B. Drag selected clips to move, drag their edges to trim, Shift-click for multi-selection.
4. Adjust transform, opacity, volume, speed and effects in the inspector. Diamonds create property keyframes. Undo/redo uses ⌘Z / ⇧⌘Z.
5. Save a `.renderproject` document. Original media is referenced without copying. Right-click a media item to relink a moved file.
6. Export H.264, HEVC or ProRes from the shared preview/export compositor.

Includes multiple video/audio tracks, lock/visibility/mute/solo, snapping, markers, insert, ripple delete, clip clipboard, asynchronous thumbnails/waveforms, recent projects, atomic saves and recovery. Effects include exposure, brightness, contrast, saturation, blur, sharpen and vignette. Supported decoding depends on macOS's installed codecs.

## Build and validate

```sh
swift build
swift test
scripts/package.sh
open dist/Render.app
```

The package script builds an ARM64 Release bundle, generates the icon, ad-hoc signs it, creates and verifies the DMG, checks an installed copy, and runs a launch smoke check. GitHub Actions runs core tests plus synthetic-media preview/export integration tests. DMGs are release assets, never committed binaries.

[Architecture and milestones](docs/DEVELOPMENT.md) · [Manual testing and limitations](docs/MANUAL_TESTS.md) · [Installation](docs/INSTALL.md)

## Release status

Version 0.1.0 establishes the functional track-editing foundation. Advanced workflows are scheduled in the development plan; unsupported features are not represented by decorative controls. This release is ad-hoc signed and not notarized. Physical-device performance profiling and the manual release checklist remain required before production use.

MIT License.
