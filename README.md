# Render

A native, non-destructive macOS video editor built with SwiftUI, AppKit, AVFoundation and a Metal-backed Core Image compositor. Render is an early-stage long-term editor project, not yet a production replacement for an established NLE.

![Render running on macOS with an automated composition test project](docs/assets/workspace.png)

## Requirements

Apple Silicon · macOS 14+ · Xcode 16.4+ for source builds. No external runtime packages.

## Working editing path

1. Import video, audio or still images (⌘I or Finder drop).
2. Double-click media to append, or drag it onto a compatible timeline track.
3. Scrub the ruler, play with Space, select with A, blade with B, split with ⌘B. Drag selected clips to move, drag their edges to trim, Shift-click for multi-selection. R selects ripple trim, O roll, Y slip, U slide, G range and Z zoom (Shift-click zooms out). Select a range and press Delete or Shift-Delete to ripple it.
4. Adjust transform, opacity, volume, speed and effects in the inspector. Diamonds create property and effect keyframes. The Animation inspector edits key timing, values, linear/ease/hold interpolation, and keyframe copy/paste. Undo/redo uses ⌘Z / ⇧⌘Z.
5. Save a `.renderproject` document. Original media is referenced without copying. Right-click a media item to relink a moved file.
6. Right-click video media to generate a 720p H.264 proxy or source-size ProRes optimized file. Select Original, Proxy or Optimized in the viewer; the toolbar task button shows generation progress and cancellation.
7. Add a Title or Caption from the Timeline menu; edit text and styling in the inspector. Import/export UTF-8 SRT captions from File.
8. Export H.264, HEVC or ProRes from the shared preview/export compositor.

Includes multiple video/audio tracks, lock/visibility/mute/solo, snapping, markers, insert, ripple delete, clip clipboard, asynchronous thumbnails/waveforms, recent projects, atomic saves and recovery. Effects include exposure, brightness, contrast, saturation, highlights, shadows, temperature, tint, blur, sharpen, vignette, opacity and chroma key. Rectangle, ellipse and editable polygon masks can limit each effect; keying includes screen colour, similarity, softness and spill suppression. Supported decoding depends on macOS's installed codecs.

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

Version 0.8.0 adds an optional magnetic primary storyline, connected clips, automatic gap removal and explicit gap clips. Version 0.7.0 added native titles, captions, SRT import/export and resolution-independent compositing. Version 0.6.0 added queued proxy/optimized-media generation, playback representation selection and persistent media caches. Version 0.5.0 added chroma key, effect masks and extended color controls. Version 0.4.0 added keyframe timing/value editing, ease/hold interpolation, keyframe copy/paste and animated effect controls. Version 0.3.0 added composition track reuse, efficient instruction generation and viewport-limited timeline drawing. Ripple/roll/slip/slide tools, range editing, overwrite, audio detach and synchronized multitrack paste arrived in 0.2.0. Advanced workflows are scheduled in the development plan; unsupported features are not represented by decorative controls. This release is ad-hoc signed and not notarized. Physical-device performance profiling and the manual release checklist remain required before production use.

MIT License.

[Download the latest release](https://github.com/Ninnja10563/Render/releases) · [Editing tool semantics](docs/EDITING.md)
