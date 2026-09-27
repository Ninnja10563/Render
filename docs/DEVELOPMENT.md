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

- 0.5.0: extended color controls, GPU-applied chroma lookup, per-effect rectangle/ellipse/polygon masks, bounded mask/cube caches and schema-1 to schema-2 migration.

- 0.6.0: serial cancellable proxy/optimized generation queue, source fingerprint checks, playback selection/offline fallback, original-only exports, persistent bounded derived-media caches and schema-3 media variants.

The future milestone numbers above describe feature order only; actual versions follow the completed, verified scope. No project-format migration was needed for 0.2 or 0.3.

## Reproducible core benchmark

`scripts/benchmark.sh` builds only RenderCore in Release configuration for both v0.2.0 and the working tree, then applies the identical 1,000-clip group-move XCTest workload on the same machine. Logs are retained in `build/baseline-benchmark.log` and `build/current-benchmark.log` and uploaded by CI. This measures core transaction latency, not sustained playback, decoding throughput, GPU utilization or real editing-session memory.

Measured on the same Apple Silicon macOS 15 runner in [validation run 36354803548](https://github.com/Ninnja10563/Render/actions/runs/36354803548): mean 1,000-clip group-edit latency was 19.3539 ms at v0.2.0 and 1.3819 ms after indexing, approximately 14× faster. These are ten-iteration Release-build core-logic measurements; they do not quantify playback FPS or GPU throughput.

## Effect model and schema 2

EffectRenderer owns the shared Core Image effect stack implementation and bounded lookup/mask caches, independently of clip playback. Masks are source-relative and receive the clip transform. Polygon rasterization is capped at 1024 pixels on its longest side; feather/expansion execute before scaling to source size. Chroma lookup stores premultiplied RGBA and executes through CIColorCubeWithColorSpace in sRGB. The Metal-backed context renders the resulting filter graph without per-frame CPU pixel readback. Animated tolerance can require regenerating a lookup table; physical-device profiling is still needed.

Schema 2 adds optional mask and keying payloads and effect kinds. ProjectStore explicitly migrates schema-1 documents on load; saves write schema 2, so older apps reject them rather than misread them. Original files are not rewritten during opening.

## Media representations and schema 3

MediaVariant records a generated URL, representation type and source fingerprint (path, size, modification date). Playback resolves a matching existing variant; changed originals, missing or corrupt variants fall back to the original with a viewer notice. When online, audio remains at original quality. Export always invokes the builder in Original mode. Offline proxy editing is supported, but final export requires originals. Project schemas 1 and 2 migrate to schema 3 without dropping existing edits.

BackgroundTasks serializes media generation, records progress/errors and supports queued/active cancellation. MediaTranscoder publishes an adjacent staging file only after encode/duration/source-identity checks. Switching documents cancels pending work; completion also verifies project/media identity before an undoable attachment. Generated files are durable references, not evictable cache entries. MediaCache separately stores disposable metadata/posters/waveforms, keyed with SHA-256 over source identity and generation options, capped at 256 MB and 4096 entries; a new import receives a fresh asset UUID.
