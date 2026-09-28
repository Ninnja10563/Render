import SwiftUI
import UniformTypeIdentifiers
import RenderCore

struct TimelineLaneView: View {
    @ObservedObject var session: EditorSession
    let track: TimelineTrack
    let contentWidth: CGFloat
    let height: CGFloat
    let visibleRange: ClosedRange<CGFloat>
    private var visibleClips: [TimelineClip] {
        track.clips.filter { clip in
            let x = session.fps.seconds(clip.start) * session.pointsPerSecond
            let end = session.fps.seconds(clip.end) * session.pointsPerSecond
            return end >= visibleRange.lowerBound && x <= visibleRange.upperBound
        }
    }
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(EditorStyle.canvas)
                .overlay { if session.selectedTrack == track.id { Color.primary.opacity(0.035).allowsHitTesting(false) } }
                .onTapGesture {
                    session.closeSource(); NSApp.keyWindow?.makeFirstResponder(nil)
                    session.selectedTrack = track.id; session.selection = []; session.selectedRange = nil
                }
                .contextMenu { TrackContextMenu(session: session,track: track) }
            ForEach(visibleClips) { clip in
                ClipTile(session: session,clip: clip,track: track,visibleRange: visibleRange)
                    .frame(width: max(3,session.fps.seconds(clip.duration) * session.pointsPerSecond),height: height - 10)
                    .offset(x: session.fps.seconds(clip.start) * session.pointsPerSecond,y: 5)
            }
            Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1).offset(y: height - 1)
        }.frame(width: contentWidth,height: height)
            .onAppear { TimelineRenderProbe.appear(track.id) }
            .onDisappear { TimelineRenderProbe.disappear(track.id) }
            .overlay(alignment: .leading) { rangeHighlight }
            .overlay { toolInteraction }
            .onDrop(of: [.text],isTargeted: nil,perform: drop)
    }
    @ViewBuilder private var rangeHighlight: some View {
        if let range = session.selectedRange, range.trackID == track.id {
            Rectangle().fill(Color.accentColor.opacity(0.18))
                .overlay { Rectangle().strokeBorder(Color.accentColor,lineWidth: 1) }
                .frame(width: session.fps.seconds(range.end - range.start) * session.pointsPerSecond)
                .offset(x: session.fps.seconds(range.start) * session.pointsPerSecond).allowsHitTesting(false)
        }
    }
    @ViewBuilder private var toolInteraction: some View {
        if session.tool == .range {
            Color.clear.contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 1).onChanged { value in
                let a = session.snap(session.fps.frames(value.startLocation.x / session.pointsPerSecond))
                let b = session.snap(session.fps.frames(value.location.x / session.pointsPerSecond))
                session.closeSource(); NSApp.keyWindow?.makeFirstResponder(nil)
                session.selection = []; session.selectedTrack = track.id
                session.selectedRange = TimelineSelectionRange(trackID: track.id,start: min(a,b),end: max(a,b))
            })
        } else if session.tool == .zoom {
            Color.clear.contentShape(Rectangle()).onTapGesture {
                session.pointsPerSecond = min(240,max(10,session.pointsPerSecond * (NSEvent.modifierFlags.contains(.shift) ? 0.5 : 2)))
            }
        }
    }
    private func drop(_ providers: [NSItemProvider],at location: CGPoint) -> Bool {
        guard let provider = providers.first, !track.locked else { return false }
        _ = provider.loadObject(ofClass: String.self) { value,_ in
            guard let value, let asset = UUID(uuidString: value) else { return }
            Task { @MainActor in
                let frame = session.snap(session.fps.frames(location.x / session.pointsPerSecond))
                if session.project.storyline?.enabled == true && session.project.storyline?.trackID == track.id { session.perform(.insert(asset: asset,track: track.id,at: frame)) }
                else { session.perform(.append(asset: asset,track: track.id,at: frame)) }
            }
        }
        return true
    }
}
