import SwiftUI
import RenderCore

struct AudioFadeInspectorView: View {
    @ObservedObject var session: EditorSession
    let clip: TimelineClip
    private var fades: ClipAudioFades {
        clip.properties.audioFades ?? ClipAudioFades(start: clip.animationOffset,end: clip.animationOffset + clip.duration)
    }
    var body: some View {
        VStack(alignment: .leading,spacing: 10) {
            Text("Audio Fades").font(.system(size: 11,weight: .semibold))
            InspectorNumber(label: "Fade In (s)",value: session.fps.seconds(fades.fadeIn),range: 0...session.fps.seconds(clip.duration),reset: 0) { value in edit { $0.fadeIn = session.fps.frames(value) } }
            InspectorNumber(label: "Fade Out (s)",value: session.fps.seconds(fades.fadeOut),range: 0...session.fps.seconds(clip.duration),reset: 0) { value in edit { $0.fadeOut = session.fps.frames(value) } }
            Picker("Curve",selection: Binding(get: { fades.shape },set: { shape in edit { $0.shape = shape } })) {
                ForEach(AudioFadeShape.allCases,id: \.self) { Text($0.label).tag($0) }
            }.font(.system(size: 10))
            if fades.start != clip.animationOffset || fades.end != clip.animationOffset + clip.duration {
                Text("This edit retains the original fade envelope. Changing a fade attaches it to this clip’s edges.").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Divider()
        }
    }
    private func edit(_ change: (inout ClipAudioFades) -> Void) {
        var value = fades
        value.start = clip.animationOffset; value.end = clip.animationOffset + clip.duration
        value.fadeIn = min(value.fadeIn,clip.duration); value.fadeOut = min(value.fadeOut,clip.duration)
        change(&value)
        var properties = clip.properties; properties.audioFades = value
        session.perform(.properties(clip: clip.id,properties))
    }
}
