# Implementation status

This is the development status for 0.26.0. A published DMG means that milestone passed its automated release gates; it does not mean Render is a production-equivalent replacement for an established editor.

## Implemented editing path

- Native SwiftUI/AppKit workspace with resizable panels, independent browsers/audio controls, workspace presets, fullscreen, and preview-resolution choices.
- Reference-based projects, atomic writes, recent projects, recovery snapshots, relinking, schema migration, focused-field save commits, and document-wide undo/redo.
- Persistent, context-aware editing shortcut customization with conflict checks and native recording.
- Independent source viewer, persistent in/out marks and range-based append/insert/overwrite.
- Async metadata, thumbnails, filmstrips, waveforms, bounded caches and background proxy/optimized generation. Final export resolves originals.
- Multiple video/audio tracks, selection, horizontal and cross-track move, trim, split, clipboard, insert/overwrite, ripple operations, locks, visibility, mute/solo, snapping, markers, range editing and timeline virtualization.
- Optional primary storyline, gaps, connected clips and magnetic reconciliation. Selection, blade, trim, ripple, roll, slip, slide, range and zoom tools.
- Shared preview/export compositor: transforms, crop, flips, blend modes, stackable image/color effects, chroma key and rectangle/ellipse/polygon masks. Reusable keyframes with linear/eased/hold interpolation.
- Titles and captions, SRT import/export, static clip speeds, source-handle transitions, volume animation, audio fades, reviewed waveform synchronization, and decoded-input peak/RMS meters.
- Clip EQ, compressor, sample peak limiter and noise gate with ordered stacks. Source-continuous blade edits retain processor state.
- Compound creation, source navigation/editing, nested rendering/audio, shared sources, root persistence and restricted lossless break-apart.
- Multicam source definitions, manual offsets, paged angle previews and undoable angle cuts. Reverse viewer fallback when native reverse is unavailable.
- H.264/HEVC/ProRes export, resolution/frame-rate controls, H.264/HEVC bitrate presets/custom bitrate, progress/cancellation and staged publication.

## Remaining engineering work

1. Audio routing: proper mono/stereo pan and channel configuration, summed master/compound buses and meters, bus processing, processor automation and spectral noise reduction.
2. Advanced retiming: reverse clips, freeze frames, speed ramps/curves and matching time-stretch/export behavior. Reverse viewer transport does not implement reverse clip export.
3. Multicam: fixed master-audio routing, media timecode synchronization, drift correction, and uninterrupted live switching. Current angle cuts pause for composition rebuilding.
4. Editing refinements: native menu shortcut customization, drag edge auto-scroll, and long-session interaction testing.
5. Extensibility: a stable custom Metal shader/plugin ABI, custom keyframe curves, and future tracking/transcription adapters. Existing modular source architecture does not imply a shipped third-party plugin system.
6. Qualification: physical M-series CPU/GPU/memory/disk profiling, long-form projects, device audio latency, subjective listening, broader media/codec fixtures, manual recovery/storage/permission failure drills, and accessibility/light-mode/multiple-display review.
7. Distribution: Developer ID signing and notarization require the owner's Apple developer credentials. Current packages are explicitly ad-hoc signed development prereleases.

## Validation evidence and limits

The macOS ARM64 CI builds Debug and Release, runs core and native-media integration tests, runs C audio DSP sanitizers, compares the core editing benchmark, builds and verifies a DMG, installs its app, launches an editing smoke workflow, and captures compact/wide editing workspaces, audio, export, empty states, shortcuts and the source viewer in dark and light appearances. Release jobs repeat native checks before publishing the DMG and checksum. Tests inspect real decoded pixels/audio, not just project metadata.

The CI host is a macOS VM. These checks cannot establish physical M1–M5 performance, all supported codec/device behavior, subjective editing quality, or production reliability by themselves. See MANUAL_TESTS.md and the versioned release notes for the precise milestones and limitations.
