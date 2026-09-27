# Manual release verification

CI checks are automated, not a claim that this checklist was performed by a human.

- Install from mounted DMG into /Applications; open under Gatekeeper; verify icon and version.
- Test on physical M1–M5 Macs and macOS 14 onward; retina/external displays, fullscreen, light/dark appearances.
- Import MOV/MP4 H.264, HEVC, ProRes, rotated iPhone video, VFR phone video, WAV/AAC/MP3/M4A and PNG/JPEG/TIFF. Test corrupt, missing and inaccessible files independently.
- Finder multi-file drop, double-click append, library-to-track drop, relink moved media.
- Play/pause/J-K-L and frame-step; rapidly scrub then edit while composition preparation is pending.
- Verify range delete across clips and gaps, ripple leading/trailing trims, rolls at both edges, slips at source boundaries, slides with/without neighbors, overwrite preserving both sides, audio detach and synchronized multitrack paste.
- Select multiple clips, drag, trim handles, split, cut/copy/paste, insert, delete and ripple delete. Check lock, mute, solo and visibility. Undo/redo each action.
- Toggle magnetic mode on a video track, choose another primary track, preserve explicit gaps, reorder groups left/right, insert through a connected anchor, split/trim anchors and verify attachments. Delete anchors with connected/locked tracks, undo/redo, copy/paste groups, disconnect and return to traditional editing. Collisions on connected tracks should reject the transaction without changing the project.
- Inspect source boundaries at 23.976/29.97 fps; confirm non-drop-frame display and no A/V drift on long files.
- Test independent scaling, animated anchors/crop, full crop to transparency, flips and all blend modes across preview/export. Verify 100% viewer mode on Retina and non-Retina monitors and drag-to-pan limits; switch screens while paused. Commit numeric fields with Return and focus loss, including changing clip selection while a field is active.
- Animate transform/opacity/volume and effect amounts; edit key times/values and all interpolation modes, select/copy/paste/delete keys, reject occupied destinations, undo/redo, save/reopen; split and trim animated clips and verify continuity. Stack/reorder/disable/reset/remove effects.
- Key green/blue-screen footage, adjust tolerance/softness/spill, check thin edges and semi-transparent foregrounds. Compare preview/export. Test rectangle/ellipse/polygon masks, vertex edits, inversion, feather/expansion, rotated/scaled clips and mask undo. Test old schema-1 projects and save/reopen the migrated document.
- Save/reopen/Save As/duplicate, cancel close, cancel open, cancel save, corrupt project, disk-full and permission failure. Edit again during a save/close request and verify newer edits keep the document open. Rapidly request different projects and verify the newest request wins. Kill app after an edit, reopen and recover.
- Queue proxy and optimized media, cancel queued/active work, edit during generation, switch/open projects mid-job, quit during encoding. Switch playback modes; delete/corrupt proxies or move originals; verify fallback notices and offline proxy playback. Export while Proxy is selected and verify original quality. Confirm persistent thumbnail/waveform reuse and source-change invalidation.
- Add/edit title and caption clips, Unicode/RTL/multiline text, missing fonts, font weight, outline/shadow/background, transforms/effect masks/keyframes and copy/paste. Verify SRT UTF-8 BOM/CRLF import, overlapping cues, timing trims, hidden-track exclusion on SRT export, and Unicode round trips. Compare 720p/4K and different-aspect exports for preserved positions/effect sizes.
- Export H.264/HEVC/ProRes at each size and rate. Compare frames and audio to preview. Cancel export and verify no partial final file. Try a destination matching source media and an existing file.
- Stress long projects with many tracks/clips. Profile CPU, GPU, memory and disk with Instruments. Document limits before describing Render as production ready.

## Current limitations needing development

No compound clips, multicam, transitions, reverse export, speed ramps, pan/EQ/compressor, meters, customizable shortcuts, full filmstrip generation. No HDR/color-management workflow beyond SDR sRGB compositing. No advanced bitrate controls. One project window and one recovery slot. Snapshot undo history needs memory profiling on large projects. Composition reuses tracks per timeline lane; physical-device large-timeline and long-duration testing is still required.

Effect masks use a bounded 1024-pixel raster before GPU feathering/expansion and scaling; very detailed high-resolution mattes require further work. The chroma key uses a 32³ lookup table with a bounded cache; it is not yet a production keyer with matte cleanup/tracking. Mask geometry and key colour/softness/spill are static; effect amount supports keyframes.

Generated media lives in Application Support/Render/Generated Media and is referenced by projects. It is not automatically garbage-collected: keep referenced files, or remove unused generated files in Finder. Derived metadata/poster/waveform caches in Caches/Render/Media are capped at 256 MB / 4096 entries and may be discarded. Generation processes one media item at a time; originals remain required for final export.

Titles use Core Text and installed fonts, with a 64 MB raster cache and a 128 MB single-raster limit. Subtitle export writes text/timing from caption clips on visible tracks; SRT does not preserve Render styling. No transcription or karaoke/word-level subtitle system yet.

Magnetic connections are one level deep and anchor to primary-storyline clips. Moving a clip off the primary track detaches its dependents; deleting an anchor in magnetic mode removes its connected clips. Connected-track overlaps are rejected rather than automatically creating new lanes. Reassigning the primary track clears existing connections as one undoable operation.
