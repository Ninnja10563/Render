import SwiftUI
import RenderCore

/// The same commands are available from a track header and its empty lane.
struct TrackContextMenu: View {
    @ObservedObject var session: EditorSession
    let track: TimelineTrack
    var body: some View {
        Button("Select Clips on Track") {
            session.closeSource(); NSApp.keyWindow?.makeFirstResponder(nil)
            session.selectedRange = nil
            session.selectedTrack = track.id
            session.selection = Set(track.clips.map(\.id))
        }.disabled(track.clips.isEmpty)
        Button("Paste at Playhead") { session.closeSource(); NSApp.keyWindow?.makeFirstResponder(nil); session.selectedTrack = track.id; session.paste() }
            .disabled(track.locked || !session.hasTimelineClipboard)
        Divider()
        Toggle("Lock Track",isOn: state(\.locked))
        if track.kind == .video { Toggle("Hide Video",isOn: state(\.hidden)) }
        Toggle("Mute Track",isOn: state(\.muted))
        Toggle("Solo Track Audio",isOn: state(\.solo))
        if track.kind == .video {
            Button("Use as Primary Storyline") {
                session.perform(.storyline(enabled: session.project.storyline?.enabled ?? false,track: track.id))
            }.disabled(track.locked)
        }
        Divider()
        Button("Add Video Track") { session.perform(.addTrack(.video)) }
        Button("Add Audio Track") { session.perform(.addTrack(.audio)) }
    }
    private func state(_ key: WritableKeyPath<TimelineTrack,Bool>) -> Binding<Bool> {
        Binding(get: { track[keyPath: key] },set: { value in
            var next = track; next[keyPath: key] = value
            session.perform(.trackState(track: track.id,locked: next.locked,hidden: next.hidden,muted: next.muted,solo: next.solo))
        })
    }
}
