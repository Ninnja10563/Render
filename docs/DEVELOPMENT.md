# Render development

## Repository audit — 2026-09-28

The starting repository at 0cc2977 contained LICENSE only, with no source, build system, tests, tags, or releases. The working tree was clean. GitHub Actions and repository write permissions are available. The authoring environment is ARM64 Linux with no Swift or Apple SDK; native build, integration tests, packaging, and launch smoke checks must run on macOS CI. No pre-existing functionality could be built or launched.

## Architecture

Swift Package Manager, macOS 14+, Apple Silicon. No third-party runtime dependencies.

- RenderCore: value-semantic, Codable project graph; rational frame rate; integer frame editing; validated transactional commands; keyframe and effect models; atomic project storage.
- RenderMedia: asynchronous AVFoundation media analysis; thumbnails and waveforms; shared composition for playback/export; Core Image compositor using a Metal-backed context.
- RenderApp: SwiftUI/AppKit workspace, session orchestration, macOS UndoManager, timeline interaction, inspector, file panels, recovery and export UI.

Frame positions use project frames; source ranges use seconds to accommodate differing media rates. Every command validates a complete candidate project before committing. UI uses a single UndoManager for all project mutations. Playback rebuilds are cancellable and revision checked. Export captures an immutable project snapshot and always reads source media.

## Milestones and release gates

1. 0.1: usable track editor, native workspace, import, project I/O/recovery/relink, frame-accurate edits, playback/compositing, basic effects, speed, audio, export; core and media integration tests; ARM64 app/DMG release.
2. Timeline depth: insert/overwrite UI, range/roll/slip/slide tools, connected clips, magnetic mode, filmstrip virtualization and stress benchmarks.
3. Animation/color: keyframe editor, extended color, crop, masks, chroma key and transition editing with preview/export parity.
4. Audio and titles: meters, automation, fades, pan/channel routing, titles, captions and SRT.
5. Media workflows: persistent cache, proxies/optimized media, background queue, compound clips.
6. Advanced workflows: multicam synchronization, speed ramps, tracking, plugin interfaces and performance profiling on physical M1–M5 devices.

Each substantial milestone gets tests, version, commits, tag, Release app, verified DMG and GitHub release. A macOS runner can verify programmatic launch and rendering but cannot substitute for human usability checks. No production-quality claim until manual workflow, recovery, performance and installation gates are met. Signing/notarization requires a developer identity, which is not present in the repository.

## Validation

`swift test` and `swift build -c release --arch arm64` on a Mac. `scripts/package.sh` creates the app and disk image. `scripts/smoke.sh` launches the built bundle. CI validates synthetic media through composition/export and probes the output. See MANUAL_TESTS.md for human release checks. The initial CI bootstrap must be pushed before native checks are possible in this Linux environment; subsequent publication is gated on CI success.

## Implemented releases

- 0.1.0: native track-editor foundation, 29 automated tests and an installed-app editing/launch check; ARM64 DMG published.
- 0.2.0: ripple/roll/slip/slide/range/overwrite editing, audio detach and synchronized multitrack paste; 42 tests including 400 deterministic mixed edits; ARM64 DMG published.
- 0.3.0: composition track reuse, per-build source cache, instruction boundary sweep, indexed command lookup, isolated transport state and viewport-limited clip/ruler/waveform rendering.

- 0.4.0: transactional keyframe timing/value/interpolation editing, key selection/copy/paste/removal, animated effect inspector, phase-preserving trim/split serialization tests and multi-frame preview/export parity.

The future milestone numbers above describe feature order only; actual versions follow the completed, verified scope. No project-format migration was needed for 0.2 or 0.3.

## Reproducible core benchmark

`scripts/benchmark.sh` builds only RenderCore in Release configuration for both v0.2.0 and the working tree, then applies the identical 1,000-clip group-move XCTest workload on the same machine. Logs are retained in `build/baseline-benchmark.log` and `build/current-benchmark.log` and uploaded by CI. This measures core transaction latency, not sustained playback, decoding throughput, GPU utilization or real editing-session memory.

Measured on the same Apple Silicon macOS 15 runner in [validation run 36354803548](https://github.com/Ninnja10563/Render/actions/runs/36354803548): mean 1,000-clip group-edit latency was 19.3539 ms at v0.2.0 and 1.3819 ms after indexing, approximately 14× faster. These are ten-iteration Release-build core-logic measurements; they do not quantify playback FPS or GPU throughput.
