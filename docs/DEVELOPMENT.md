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

- 0.7.0: generated title/caption clips, Core Text rendering, typography/styling inspector, overlapping SRT cue import/export, schema-4 optional clip sources, and resolution-independent final compositing.

- 0.8.0: optional magnetic primary storyline, source-phase-aware connections, group reorder/delete, explicit gap clips, split/insert reconnection, copied-anchor remapping and schema-5 timeline settings.

- 0.9.0: independently animated scale/anchor/crop, flips, blend modes, sequence-space geometry tests, actual-pixel viewer zoom/panning and schema-6 geometry payload.

- 0.10.0: viewport-indexed filmstrip requests, source-time/speed mapping, cancellable bounded image decoding and persistent frame caches.

- 0.11.0: six source-handle cut transitions, paired rendering, bounded overlapping composition tracks, audio crossfade envelopes, duration inspector and schema-7 transition links.

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

## Generated clips and schema 4

TimelineClip holds either a media asset ID or embedded TitleContent, validated as mutually exclusive. Titles have no fake source file and occupy ordinary video tracks, retaining the same edit/animation/effect machinery. Schema-1 through schema-3 files migrate with their media IDs intact. TitleRenderer uses Core Text, rasterizes only active titles, and caches up to 64 MB of cropped text images.

RenderInstruction retains the sequence design size separately from export render size. Clip positions, effect radii, title fonts and masks evaluate in design coordinates; the final image scales uniformly into the output rectangle with letterboxing where aspect ratios differ. This fixes position/effect-size drift across export resolutions.

## Magnetic editing and schema 5

StorylineSettings names a primary video track independently of track order. MagneticEditing reconciles primary packing and one-level connections before normal transaction validation, so lock/overlap/source errors remain atomic. Connections store anchor IDs and timeline-relative offsets; leading trims account for animation/source phase changes. Splitting an anchor reconnects later children to the right segment, and multitrack paste remaps copied anchor identities. Gap clips are generated black sources with explicit duration. Traditional mode keeps gaps and may retain explicit connections; disconnect commands remove grouping.

## Geometry and schema 6

ClipGeometry is an optional payload; older clips retain centered anchors, uniform scale, no crop/flip and Normal blending. Animation parameter ranges are shared by core validation and editing. Crop removes source-relative pixels without reframing; fully cropped layers are skipped. Anchor movement alone retains unscaled placement, while rotation and scaling pivot around the selected source-relative anchor. The viewer interprets 100% as one sequence pixel per physical display pixel and updates backing scale when moving between displays.

## Timeline filmstrips

FilmstripView derives cell indices from the visible timeline interval, so requests change at cell boundaries rather than every scroll pixel. MediaLibrary maps requested source times to 100 ms cache keys, returns frames in request order (including duplicates), and caps each batch at 128 frames. A shared two-permit actor limits poster/filmstrip AVAssetImageGenerator work. Cancelled work releases permits, and in-flight batches retain their cached images even if the bounded global image cache is evicted. No project schema change.

## Transitions and schema 7

Outgoing ClipTransition links to the adjacent right clip. Validation checks both source handles at clip speed; TransitionWindow straddles the unchanged cut. CompositionBuilder expands only rendering source ranges and reuses a second video/audio slot when intervals overlap, preserving sequence duration. Instructions include active transition handles. The compositor evaluates each pair once, combines transformed/effected inputs with the lower-layer canvas, and preserves the requested blend modes. AudioAutomation multiplies volume curves by bounded crossfade ramps. Broken links are pruned as part of structural-edit undo transactions; explicit transition authoring instead reports invalid handles.

## Audio fades and schema 8

ClipProperties optionally carries ClipAudioFades, whose frame interval shares the volume animation coordinate system. Structural edits retain the envelope with animationOffset, avoiding an audible fade restart at a blade cut. Authoring a duration or shape attaches the envelope to the currently selected clip edges. Bounded piecewise ramps multiply automation, clip fades and transition envelopes before AVAudioMix setup; preview and export use the same composition builder.

## Audio synchronization

AudioSyncAnalyzer reads source in-point windows into 100 Hz RMS envelopes with a two-minute cap, using decoded timestamps and channel energy without polarity cancellation. AudioSynchronization uses normalized correlation over bounded offsets, then full-sample refinement of separated candidates. Ambiguous or weak matches fail explicitly. AudioSyncView retains the analyzed project snapshot, validates a proposed normal move transaction, and only applies a reviewed result when the snapshot still matches. Cancellation stops analysis; no decoded media or derived envelope enters project storage.

## Controlled export

ExportQuality computes bitrate targets independently of encoder setup. Codec-managed export retains AVAssetExportSession; explicit-quality H.264/HEVC uses ControlledEncoder, an actor owning AVAssetReader/AVAssetWriter. VideoCompositionOutput invokes the same compositor used by preview, and AudioMixOutput applies automation before stereo AAC encoding. The loop services both ready inputs, yields under backpressure, and never accumulates decoded frames. ExportService cancellation propagates to the encoder task and keeps partial files private until completion.

Apple API references: [reader/writer composition export](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/AVFoundationPG/Articles/05_Export.html), [custom compositor](https://developer.apple.com/documentation/avfoundation/avassetreadervideocompositionoutput/customvideocompositor), [bitrate](https://developer.apple.com/documentation/avfoundation/avvideoaveragebitratekey).

## Multicam and schema 9

MulticamSource owns named CameraAngle references with source-time offsets. Timeline clips keep an ordinary assetID plus validated source/angle membership, so decoding, proxies, effects and export retain the established source pipeline. Switching maps current source time through the old/new offsets; cutting also advances animation phase and reconnects storyline children. Definitions are reusable and media is never duplicated. The angle viewer limits live decoders to four visible tiles, mutes audition audio and synchronizes source time while preserving independent camera durations. Structural edits preserve membership; detached audio explicitly drops it.

## Vertical timeline viewport

TimelineViewport computes one fixed-height track range for both the frozen headers and horizontal lane content. Leading/trailing spacers retain complete scroll geometry while only visible rows plus two-row overscan construct clip views. Removing an offscreen FilmstripView cancels its task; shared cache/decode-gate limits remain unchanged. Transport redraws stay isolated in TimelinePlayhead. Core tests exercise large track lists and scrolling boundary coverage; physical-device input latency and GPU/memory measurements remain separate release work.
