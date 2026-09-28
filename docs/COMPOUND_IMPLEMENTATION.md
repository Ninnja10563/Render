# Compound implementation work in progress

This branch is not release-ready. Schema 10 and core commands are being built on the hierarchical compositor. Do not expose UI until nested playback/export, root-document persistence and navigation are validated.

Remaining integration:

- Composition planning must recursively map local child frames into global composition time. A mapping uses globalFrame = offset + localFrame * scale; entering a parent multiplies scale by 1 / parent.speed and offsets by parent.start - parent.sourceIn * localFPS / parent.speed. Preserve separate child canvas sizes/frame rates. Clamp source insertions to parent render windows, including transition handles. Graph groups retain child-local clip properties and timing.
- Compile instruction boundaries from global leaf windows; prune inactive graph branches for each interval. Reuse video/audio composition tracks across nonoverlapping intervals. Keep source asset owners alive as before. Preview proxies and original-only export must still work.
- Audio must multiply leaf and ancestor volume/keyframe/fade envelopes in global time. Preserve hold jumps, mute/solo scoping and source audio ranges, with bounded ramp sampling. Do not silently omit parent audio settings.
- EditorSession needs a persistent root document independent of its active timeline projection. Every undo snapshot must restore the root document even after navigation. Save/recovery/export use the root; preview/editing use the active context. Context replacement merges global media/camera/compound definitions and validates all source references. New/open resets navigation. Clipboard should import reachable compound definitions when moving between contexts and reject cycles.
- Creation moves selected clips into a reusable source without copying media. Current core restrictions reject cross-boundary transitions or intervening video that would change layer order. Break-apart rejects group-dependent processing that cannot be represented by independent clips; never silently discard it. Magnetic restoration needs explicit gap coverage and reconnection tests.
- Add core graph/cycle/depth/context/undo/serialization tests; real nested playback/export tests for transforms, effects, parent opacity, transitions, retiming and audio; installed-app create/open/edit/return/break-apart/save/reopen checks.
