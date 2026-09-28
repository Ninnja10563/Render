import SwiftUI
import UniformTypeIdentifiers
import RenderCore

struct TimelineView: View {
    @ObservedObject var session: EditorSession
    @State private var scrollOffset: CGFloat = 0
    @State private var viewportWidth: CGFloat = 1000
    @State private var verticalOffset: CGFloat = 0
    @State private var viewportHeight: CGFloat = 300
    private let headerWidth: CGFloat = 148
    private let laneHeight: CGFloat = 70
    var contentWidth: CGFloat { max(1000,session.fps.seconds(session.project.duration) * session.pointsPerSecond + 300) }
    private var visibleRows: Range<Int> {
        TimelineViewport.rows(count: session.project.tracks.count,rowHeight: laneHeight,headerHeight: 28,offset: verticalOffset,height: viewportHeight)
    }
    private var visibleTracks: ArraySlice<TimelineTrack> { session.project.tracks[visibleRows] }
    private var leadingSpace: CGFloat { CGFloat(visibleRows.lowerBound) * laneHeight }
    private var trailingSpace: CGFloat { CGFloat(session.project.tracks.count - visibleRows.upperBound) * laneHeight }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text("TIMELINE").font(.system(size: 10,weight: .semibold)).foregroundStyle(.secondary)
                Picker("Tool", selection: $session.tool) {
                    ForEach(EditingTool.allCases,id: \.self) { tool in Label(tool.rawValue,systemImage: tool.symbol).tag(tool) }
                }.pickerStyle(.menu).frame(width: 120).labelsHidden().help("A Selection · B Blade · T Trim · R Ripple · O Roll · Y Slip · U Slide · G Range · Z Zoom")
                Toggle("Magnetic",isOn: Binding(get: { session.project.storyline?.enabled == true },set: { session.setMagnetic($0) })).toggleStyle(.button).help("Pack the primary storyline and move connected clips with their anchors")
                Toggle(isOn: $session.snapping) { Image(systemName: "point.topleft.down.curvedto.point.bottomright.up") }.toggleStyle(.button).help("Snapping (N)")
                Menu { Button("Video Track") { session.perform(.addTrack(.video)) }; Button("Audio Track") { session.perform(.addTrack(.audio)) } } label: { Image(systemName: "plus") }.menuStyle(.borderlessButton).frame(width: 24)
                Button { session.split() } label: { Image(systemName: "scissors") }.buttonStyle(.plain).help("Split at playhead (⌘B)")
                Spacer()
                Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
                Slider(value: $session.pointsPerSecond, in: 10...240).frame(width: 100).help("Timeline zoom")
                Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary)
            }.controlSize(.small).padding(.horizontal,12).frame(height: 40)
            Divider()
            ScrollView(.vertical) {
                HStack(alignment: .top,spacing: 0) {
                    VStack(spacing: 0) {
                        Text("TRACKS").font(.system(size: 9,weight: .semibold)).foregroundStyle(.tertiary).frame(width: headerWidth,height: 28,alignment: .leading).padding(.leading,12)
                        Color.clear.frame(height: leadingSpace)
                        ForEach(visibleTracks) { track in TrackHeader(session: session, track: track).frame(width: headerWidth,height: laneHeight) }
                        Color.clear.frame(height: trailingSpace)
                    }.frame(width: headerWidth)
                    Divider()
                    ScrollView(.horizontal) {
                        VStack(spacing: 0) {
                            ruler
                            Color.clear.frame(height: leadingSpace)
                            ForEach(visibleTracks) { track in
                                TimelineLaneView(session: session,track: track,contentWidth: contentWidth,height: laneHeight,visibleRange: (scrollOffset - 200)...(scrollOffset + viewportWidth + 200))
                            }
                            Color.clear.frame(height: trailingSpace)
                        }
                        .overlay(alignment: .topLeading) {
                            TimelinePlayhead(transport: session.transport,frameRate: session.fps,pointsPerSecond: session.pointsPerSecond)
                        }
                        .background(NativeScrollViewport { origin,size in
                            TimelineRenderProbe.horizontalOffset(origin.x,project: session.project.id)
                            if scrollOffset != origin.x { scrollOffset = origin.x }
                            if viewportWidth != size.width { viewportWidth = size.width }
                        }.frame(width: 0,height: 0))
                    }
                }
                .background(NativeScrollViewport { origin,size in
                    if verticalOffset != origin.y { verticalOffset = origin.y }
                    if viewportHeight != size.height { viewportHeight = size.height }
                }.frame(width: 0,height: 0))
            }
        }.background(Color(nsColor: .underPageBackgroundColor))
    }
    private var ruler: some View {
        let origin = max(0,scrollOffset - 200)
        let visibleWidth = min(contentWidth,viewportWidth + 400)
        return ZStack(alignment: .topLeading) {
            Canvas { context,size in
                let step = session.pointsPerSecond < 30 ? 5 : (session.pointsPerSecond < 80 ? 2 : 1)
                let first = max(0,Int(origin / session.pointsPerSecond) / step * step)
                let last = Int((origin + visibleWidth) / session.pointsPerSecond) + step
                for second in stride(from: first,through: last,by: step) {
                    let x = Double(second) * session.pointsPerSecond - origin
                    var path = Path(); path.move(to: CGPoint(x: x,y: 20)); path.addLine(to: CGPoint(x: x,y: 28))
                    context.stroke(path,with: .color(.secondary.opacity(0.5)),lineWidth: 1)
                    context.draw(Text(session.fps.timecode(session.fps.frames(Double(second)))).font(.system(size: 9,design: .monospaced)).foregroundColor(.secondary),at: CGPoint(x: x + 5,y: 10),anchor: .leading)
                }
                for marker in session.project.markers {
                    let x = session.fps.seconds(marker.frame) * session.pointsPerSecond - origin
                    if x >= -5 && x <= visibleWidth + 5 { context.fill(Path(CGRect(x: x - 2,y: 18,width: 5,height: 9)),with: .color(.orange)) }
                }
            }.frame(width: visibleWidth,height: 28).offset(x: origin)
        }.frame(width: contentWidth,height: 28).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in NSApp.keyWindow?.makeFirstResponder(nil); session.pause(); session.seek(session.fps.frames(value.location.x / session.pointsPerSecond)) })
    }
}

private struct TrackHeader: View {
    @ObservedObject var session: EditorSession
    let track: TimelineTrack
    var body: some View {
        VStack(alignment: .leading,spacing: 10) {
            HStack {
                Image(systemName: track.kind == .video ? "film" : "waveform").foregroundStyle(.secondary)
                Text(track.name).fontWeight(.medium)
                if session.project.storyline?.trackID == track.id { Image(systemName: "link").font(.system(size: 9)).help("Primary storyline") }
            }.font(.system(size: 11))
            HStack(spacing: 12) {
                Button { update(locked: !track.locked) } label: { Image(systemName: track.locked ? "lock.fill" : "lock.open") }.help(track.locked ? "Unlock track" : "Lock track")
                if track.kind == .video { Button { update(hidden: !track.hidden) } label: { Image(systemName: track.hidden ? "eye.slash" : "eye") }.help("Toggle video visibility") }
                Button { update(muted: !track.muted) } label: { Image(systemName: track.muted ? "speaker.slash.fill" : "speaker.wave.2") }.help("Mute track")
                Button { update(solo: !track.solo) } label: { Text("S").fontWeight(track.solo ? .heavy : .regular).foregroundStyle(track.solo ? Color.orange : Color.secondary) }.help("Solo track audio")
            }.font(.system(size: 10)).buttonStyle(.plain).foregroundStyle(.secondary)
        }.padding(.horizontal,12).frame(maxWidth: .infinity,maxHeight: .infinity,alignment: .leading)
            .background(session.selectedTrack == track.id ? Color.accentColor.opacity(0.09) : .clear)
            .contentShape(Rectangle()).onTapGesture { session.selectedTrack = track.id }
            .contextMenu {
                if track.kind == .video { Button("Use as Primary Storyline") { session.perform(.storyline(enabled: session.project.storyline?.enabled ?? false,track: track.id)) }.disabled(track.locked) }
            }
            .overlay(alignment: .bottom) { Divider() }
    }
    func update(locked: Bool? = nil, hidden: Bool? = nil, muted: Bool? = nil, solo: Bool? = nil) {
        session.perform(.trackState(track: track.id,locked: locked ?? track.locked,hidden: hidden ?? track.hidden,muted: muted ?? track.muted,solo: solo ?? track.solo))
    }
}


private struct TimelinePlayhead: View {
    @ObservedObject var transport: TransportState
    let frameRate: FrameRate
    let pointsPerSecond: Double
    var body: some View {
        Rectangle().fill(Color.accentColor).frame(width: 1.5)
            .offset(x: frameRate.seconds(transport.playhead) * pointsPerSecond).allowsHitTesting(false)
    }
}
