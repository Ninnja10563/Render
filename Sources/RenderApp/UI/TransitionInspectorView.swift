import SwiftUI
import RenderCore

struct TransitionInspectorView: View {
    @ObservedObject var session: EditorSession
    let clip: TimelineClip
    private var next: TimelineClip? {
        guard let location = session.project.location(clip.id) else { return nil }
        return session.project.tracks[location.track].clips.first { $0.start == clip.end && $0.id != clip.id }
    }
    var body: some View {
        VStack(alignment: .leading,spacing: 8) {
            Text("Transition to Next Clip").font(.system(size: 11,weight: .semibold))
            if let next {
                Text(next.name).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                Picker("Transition",selection: Binding(get: { clip.transition?.kind.rawValue ?? "none" },set: { value in
                    guard let kind = TransitionKind(rawValue: value) else { session.perform(.transition(clip: clip.id,nil)); return }
                    let duration = clip.transition?.duration ?? min(session.fps.frames(1),min(clip.duration,next.duration))
                    session.perform(.transition(clip: clip.id,ClipTransition(rightID: next.id,kind: kind,duration: duration)))
                })) {
                    Text("None").tag("none")
                    ForEach(TransitionKind.allCases,id: \.self) { kind in Text(kind.label).tag(kind.rawValue) }
                }.font(.system(size: 10)).disabled(min(clip.duration,next.duration) < 2)
                if let transition = clip.transition {
                    InspectorNumber(label: "Duration (seconds)",value: session.fps.seconds(transition.duration),range: session.fps.seconds(2)...session.fps.seconds(min(clip.duration,next.duration)),reset: min(1,session.fps.seconds(min(clip.duration,next.duration)))) { seconds in
                        do { var changed = transition; changed.duration = max(2,try session.fps.editingFrames(seconds)); session.perform(.transition(clip: clip.id,changed)) }
                        catch { session.report(error) }
                    }
                }
                Text("Transitions straddle the cut without changing sequence length. Moving video needs spare source frames on both sides; trim the clips first if handles are unavailable. Audio crossfades over the same interval.").font(.system(size: 9)).foregroundStyle(.secondary)
            } else {
                Text("Place another clip immediately after this one on the same video track.").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Divider()
        }
    }
}
