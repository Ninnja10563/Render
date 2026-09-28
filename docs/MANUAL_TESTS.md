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
- Add every transition to adjacent clips with source handles; verify insufficient-handle errors, durations, cuts at different speeds, alpha/blend modes, audio continuity, proxy playback, structural edits and single/multitrack paste. Compare preview/export before, during and after the cut.
- Export H.264/HEVC/ProRes at each size and rate. Compare frames and audio to preview. Cancel export and verify no partial final file. Try a destination matching source media and an existing file.
- Verify filmstrip frames across cuts, trimmed and sped-up clips; scroll and zoom rapidly, cancel/reopen projects, switch proxy modes and go offline. Confirm bounded decoding and cache reuse with Instruments, including many simultaneous visible tracks.
- Stress long projects with many tracks/clips. Profile CPU, GPU, memory and disk with Instruments. Document limits before describing Render as production ready.

## Current limitations needing development

No compound clips, multicam, reverse export, speed ramps, pan/EQ/compressor, meters, customizable shortcuts. No HDR/color-management workflow beyond SDR sRGB compositing. No advanced bitrate controls. One project window and one recovery slot. Snapshot undo history needs memory profiling on large projects. Composition reuses tracks per timeline lane; physical-device large-timeline and long-duration testing is still required.

Effect masks use a bounded 1024-pixel raster before GPU feathering/expansion and scaling; very detailed high-resolution mattes require further work. The chroma key uses a 32³ lookup table with a bounded cache; it is not yet a production keyer with matte cleanup/tracking. Mask geometry and key colour/softness/spill are static; effect amount supports keyframes.

Generated media lives in Application Support/Render/Generated Media and is referenced by projects. It is not automatically garbage-collected: keep referenced files, or remove unused generated files in Finder. Derived metadata/poster/waveform caches in Caches/Render/Media are capped at 256 MB / 4096 entries and may be discarded. Generation processes one media item at a time; originals remain required for final export.

Titles use Core Text and installed fonts, with a 64 MB raster cache and a 128 MB single-raster limit. Subtitle export writes text/timing from caption clips on visible tracks; SRT does not preserve Render styling. No transcription or karaoke/word-level subtitle system yet.

Magnetic connections are one level deep and anchor to primary-storyline clips. Moving a clip off the primary track detaches its dependents; deleting an anchor in magnetic mode removes its connected clips. Connected-track overlaps are rejected rather than automatically creating new lanes. Reassigning the primary track clears existing connections as one undoable operation.

Filmstrip requests decode visible cells only, quantize source time to 100 ms, and share a two-decoder limit with media posters. Generated thumbnails are indicative source frames, not effect-rendered previews. Still images repeat their poster; titles and gaps retain labeled timeline tiles.

Transitions preserve sequence duration and require source handles on both sides of a cut. The transition duration cannot exceed either adjacent clip. Structural edits that break a pair remove that transition in the same undoable transaction. Transition audio uses linear amplitude crossfades; curve selection and independent transition audio duration are not yet exposed.

Audio fades: import a tone or music file, add both fades and switch Linear/Smooth/Equal Power. Audition and export; split halfway through the fade and confirm no restart. Trim, undo, save/reopen, then change a fade to attach it to the new edges. Check title/still/silent-video selections omit audio controls.

Audio sync: select camera audio and an external recording on separate unlocked tracks in traditional mode. Choose each as reference in turn, inspect offsets, apply/undo and audition. Try silence, repeating music, background noise, clipped recordings, long files and differing in-points. Cancel analysis and confirm no move. Test a proposed overlap and a negative timeline position; both must be rejected.

Controlled export: compare Compact/Balanced/High/Custom H.264 and HEVC with motion, effects, transitions and multiple audio tracks. Verify requested frame rates and custom dimensions; inspect output with QuickTime. Cancel during preparation, encoding and finalization; no partial destination should appear. Test a full disk and permission denial. Check UI responsiveness and actual hardware usage on physical Apple Silicon.

Focused drafts: type a position, effect value, fade duration or keyframe value without pressing Return, then use Command-S. Reopen and verify the edit. Repeat when closing an otherwise clean project, and before export. Invalid text must block save; Undo must restore the previous valid value.

Multicam: import two camera recordings, trim a reference segment, enter positive/negative source offsets and create a source. Scrub and play the angle viewer, page more than four cameras, cut at the playhead, replace a segment in the inspector, then undo/save/reopen/export. Try unavailable source ranges, speed changes, locked tracks, magnetic connections and detached audio. Verify inactive pages release their players. Cuts currently pause for rebuild; do not describe this as uninterrupted live switching.

Vertical timeline: build a sequence with hundreds of video/audio tracks, scroll vertically and horizontally together, zoom, resize panels and select distant tracks. Verify header/lane alignment, correct drop targets, continued selection and playhead geometry. Observe filmstrip decoding and memory in Instruments; only visible rows plus overscan should request frames. Test drag/trim while scrolling and switching the inspector.

## Compound timelines

- Group a multitrack selection, open its source, edit a title and audio fade, return, trim/retime the parent and compare export. Repeat with nested sources and mixed source frame rates.
- Save while editing inside a compound, close and reopen. Confirm the outer project and every source edit remain. Undo/redo both inside and outside a source; undo creation while the source is open.
- Copy a compound to another timeline, verify shared-source behavior, and try pasting into itself: the operation must be rejected without changing the document.
- Break apart an unprocessed compound; compare image/audio. Confirm transformed/effected compounds report the restriction and retain all edits. Test magnetic gaps, connections, locks, missing media and proxy fallback inside sources.

## Workspaces and preview resolution

- Resize all panels on a MacBook and external display. Switch each workspace, hide/show each panel, enter fullscreen, and verify timeline scrolling and numeric field commits.
- Search and apply an effect to multiple visual clips, undo once, and verify locked/audio selections are excluded by disabling the action.
- Change Full/Half/Quarter preview resolution with original, proxy and optimized media; verify framing, nested effects and full-resolution export remain consistent.
- Open Audio controls beside the timeline. Select clips and edit volume/fades, mute/solo tracks, undo, save and reopen.

## Audio input meters

- Play mono, stereo and multichannel sources in flat and nested timelines; compare post-volume/fade channel levels with a known test tone. Pause, seek, reverse shuttle and loop: stale readings must not remain visible.
- Switch mute/solo and workspace layouts during playback. Confirm meter updates do not stall dragging or redraw the whole editor.
- Compare output samples with metering enabled/disabled; exports must retain the same audio. Input meters are not summed master meters. Test loud overlapping inputs separately for output clipping.

## Reverse preview

- Use J/K/L and Space on long-GOP video, still/title sequences, compounds and proxy media. Test 1×/2×/4× reverse, scrubbing during reverse, and stopping at the beginning.
- Confirm the viewer and playhead stay synchronized when decoding cannot maintain the requested rate. Reverse fallback must show muted audio and clear meters.
- Change an inspector property, switch timelines, open another project, and close the app during reverse; no pending seek should affect the new item.

## Leading handles

- Extend a clip with unused leading source media and animated transform, effect and volume. Compare the retained material before/after, then undo/redo.
- Repeat with roll, slide and ripple-leading tools, connected titles and locked tracks. Real source underruns must still fail atomically.
- Extend a title, still and explicit gap earlier; slip a trimmed compound through its available source range.

## Clip audio processors

- Add EQ, compressor, sample peak limiter and gate to mono, stereo and multichannel source clips. Compare playback and each export codec, including nested timelines, speed changes and transitions.
- Bypass, reorder, reset and remove processors. Edit a focused numeric field and save; reopen and undo/redo. Try locked tracks, unsupported channel counts and compound instances.
- Split an unchanged processed clip and listen across the cut; its continuous processor state should remain. Seek, trim to a different source range, add a gap and compare predictable envelope restarts.
- Use quiet speech, transients and sustained tones to assess gate and compressor timing. Check output clipping after high fader gain and summing tracks. The sample peak limiter is pre-fader and is not a true-peak mastering limiter.
- Profile audio callback CPU and playback latency on physical Apple Silicon while dragging clips, switching layouts and exporting. Automated numerical tests do not replace listening or device profiling.

## Cross-track dragging

- Drag a single clip and a multitrack selection up/down and forward/backward. Confirm source/animation timing and relative lane spacing, then undo/redo.
- Try incompatible, locked and occupied destinations, timeline bounds, and a destination inside the selected tracks. Invalid drops must preserve the complete document.
- Move connected anchors off the primary and clips onto the magnetic primary. Confirm connected timing, packing and cleared connections.
- Press Escape mid-drag, switch editing tools, scroll the source row out of view and close the timeline. No abandoned drag should remain visible or commit later.
