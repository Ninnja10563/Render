# Timeline editing

All edits are validated against track locks, source bounds and same-track overlap before committing. Failed edits leave the project and undo history intact. Undo restores source timing, effects and animation phase together.

| Tool | Key | Gesture / behavior |
| --- | --- | --- |
| Selection | A | Drag selected clips in time; Shift/Command-click extends selection. Use the clip context menu to move to another compatible track. |
| Blade | B | Click the cut position in a clip. ⌘B splits at the playhead. |
| Trim | T | Drag an edge; dragging the body adjusts the trailing edge. Gaps remain. |
| Ripple | R | Drag an edge to shorten/extend the clip and shift following clips on that track. Leading ripple trims keep the original cut position. |
| Roll | O | Drag an edge shared with a neighbor; changes both durations and keeps their outer boundaries. Body drag rolls the right-hand edit. |
| Slip | Y | Drag the body to change the source window while keeping timeline position and duration. Requires available source handles. |
| Slide | U | Drag the body to move the clip and trim both adjacent neighbors. Requires contiguous neighbors and source handles. |
| Range | G | Drag across a track. Delete removes only the selected time interval; Shift-Delete also closes that interval on the same track. |
| Zoom | Z | Click a track to zoom in; Shift-click zooms out. The zoom slider remains available in all tools. |

N toggles snapping. M adds a marker. Track controls provide lock, visibility, mute and solo. Source media stays untouched.

Right-click library media to append, insert or overwrite at the playhead. Insert splits a clip if necessary and shifts later clips; overwrite preserves material before and after the replaced interval. The full media duration is used; source in/out marking is a future feature.

Right-click a video clip with embedded audio to detach audio. This creates a separate audio track referencing the same file, preserves timing/speed/volume automation, and mutes the original clip's audio. Undo reverses the complete operation. The resulting video and audio can be selected and moved together.

Copy/paste across multiple tracks preserves track assignment and relative synchronization. Single-track paste targets the selected compatible track. Clipboard contents are scoped to the current project. Range copy/paste is not yet implemented.

Ripple operations affect one track. They do not imply a magnetic timeline or automatically move connected clips on other tracks. Those workflows remain a separate milestone.
