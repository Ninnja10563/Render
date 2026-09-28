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

Copy/paste across multiple tracks preserves track assignment and relative synchronization. Single-track paste targets the selected compatible track. Clipboard contents are scoped to the current project. Across compound contexts, missing destination lanes are created with their original media kind; compound source definitions remain shared. Range copy/paste is not yet implemented.

Traditional ripple operations affect one track. Enable Magnetic Storyline in the Timeline menu for primary-storyline gap removal and connected-clip movement. Explicit gap clips preserve intentional empty time.

## Compound clips

Select clips and choose Create Compound Clip (⌥⌘G). Connected children are included; selection across a transition must include both sides. Intervening unselected video that would change layer order must also be included. Open the compound through its inspector, context menu or Timeline menu. Breadcrumbs return to parent timelines without creating edits.

Parent effects and opacity apply after its children composite. Audio volume, fades and automation multiply through every ancestor. Hiding a video track does not mute its sound; mute and solo retain their per-timeline scope. Parent speed and source trims map into the child's frame rate independently.

Save, recovery and video export always capture the full root document, including edits made inside sources. Compound instances share their source: editing one source changes every instance. Deleting inner clips retains source duration, so an empty source remains a valid transparent/silent interval. Extending contents grows the source without automatically changing existing instances.

Break Apart generates fresh child IDs, preserves source timing and automation phase, and keeps the reusable source definition. Group transforms/effects/speed, non-Normal child blending, solo state, differing sequence settings, or trims through transitions can prevent lossless flattening; reset those conditions first or retain the compound. Track locks remain in force. Cycles are rejected and nesting is limited to eight sources.

## Leading handles and animation

Extending a leading edge preserves the animation and audio-fade phase of the material already in the edit. When needed, internal keyframe/fade coordinates translate together so the new origin remains nonnegative. Existing fade positions are retained; adjusting a fade in the inspector reattaches it to the current clip edges. Media and compound clips still need real source handles. Generated titles, gaps and stills have no finite source boundary. Connected children stay aligned with retained content; ripple trims move that content and its connections together.
