import SwiftUI
import RenderCore

struct AudioControlsView: View {
    @ObservedObject var session: EditorSession
    @ObservedObject private var transport: TransportState
    init(session: EditorSession) { self.session = session; transport = session.transport }
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("AUDIO").font(.system(size: 10,weight: .semibold)); Spacer(); Button { session.showAudio = false } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("Hide audio controls") }.foregroundStyle(.secondary).padding(.horizontal,12).frame(height: 32)
            Divider()
            ScrollView {
                VStack(alignment: .leading,spacing: 14) {
                    if let clip = session.selectedClip, session.clipHasAudio(clip) {
                        Text(clip.name).font(.system(size: 11,weight: .semibold)).lineLimit(2)
                        let frame = Double(max(0,min(clip.duration - 1,session.playhead - clip.start)) + clip.animationOffset)
                        InspectorNumber(label: "Volume",value: clip.properties.value("volume",at: frame),range: 0...4,reset: 1) { session.setProperty("volume",value: $0,clipID: clip.id) }
                        Toggle("Mute clip",isOn: Binding(get: { clip.properties.muted },set: { value in var p = clip.properties; p.muted = value; session.perform(.properties(clip: clip.id,p)) }))
                        AudioFadeInspectorView(session: session,clip: clip)
                        AudioEffectsInspectorView(session: session,clip: clip)
                        Divider()
                    } else { Text("Select a clip with audio to adjust its level and fades.").font(.system(size: 11)).foregroundStyle(.secondary) }
                    AudioInputMetersView(meters: session.audioMeters)
                    Text("TRACKS").font(.system(size: 9,weight: .semibold)).foregroundStyle(.secondary)
                    ForEach(audioTracks) { track in audioTrackRow(track) }
                }.padding(12)
            }
        }.font(.system(size: 11))
    }
    private var audioTracks: [TimelineTrack] {
        session.project.tracks.filter { $0.kind == .audio || $0.clips.contains(where: { session.clipHasAudio($0) }) }
    }
    private func audioTrackRow(_ track: TimelineTrack) -> some View {
        HStack(spacing: 6) {
            Button(track.name) {
                session.selectedTrack = track.id
                if let clip = track.clips.first(where: { $0.start <= session.playhead && $0.end > session.playhead }) ?? track.clips.first { session.selectClip(clip.id) }
            }.buttonStyle(.plain).lineLimit(1)
            Spacer(minLength: 0)
            Toggle("M",isOn: Binding(get: { track.muted },set: { session.perform(.trackState(track: track.id,locked: track.locked,hidden: track.hidden,muted: $0,solo: track.solo)) })).help("Mute \(track.name)")
            Toggle("S",isOn: Binding(get: { track.solo },set: { session.perform(.trackState(track: track.id,locked: track.locked,hidden: track.hidden,muted: track.muted,solo: $0)) })).help("Solo \(track.name)")
        }.toggleStyle(.button).controlSize(.mini).font(.system(size: 10))
    }

}
