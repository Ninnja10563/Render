import SwiftUI
import UniformTypeIdentifiers
import RenderCore

struct TimelineView: View {
    @ObservedObject var session: EditorSession
    @ObservedObject private var shortcuts = ShortcutStore.shared
    @State private var scrollOffset: CGFloat = 0
    @State private var viewportWidth: CGFloat = 1000
    @State private var verticalOffset: CGFloat = 0
    @State private var viewportHeight: CGFloat = 300
    private let headerWidth: CGFloat = 148
    private let laneHeight: CGFloat = 70
    var contentWidth: CGFloat { max(1000,max(viewportWidth,session.fps.seconds(session.project.duration) * session.pointsPerSecond + 300)) }
    private var visibleRows: Range<Int> {
        TimelineViewport.rows(count: session.project.tracks.count,rowHeight: laneHeight,headerHeight: 28,offset: verticalOffset,height: viewportHeight)
    }
    private var visibleTracks: ArraySlice<TimelineTrack> { session.project.tracks[visibleRows] }
    private var leadingSpace: CGFloat { CGFloat(visibleRows.lowerBound) * laneHeight }
    private var trailingSpace: CGFloat { CGFloat(session.project.tracks.count - visibleRows.upperBound) * laneHeight }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Timeline").font(.system(size: 12,weight: .medium)).accessibilityAddTraits(.isHeader)
                Picker("Tool", selection: $session.tool) {
                    ForEach(EditingTool.allCases,id: \.self) { tool in Label(tool.rawValue,systemImage: tool.symbol).tag(tool) }
                }.pickerStyle(.menu).frame(width: 120).labelsHidden().help([EditorShortcutAction.selectTool,.bladeTool,.trimTool,.rippleTool,.rollTool,.slipTool,.slideTool,.rangeTool,.zoomTool].map { "\(shortcuts.label($0)) \($0.title)" }.joined(separator: " · "))
                Toggle("Magnetic",isOn: Binding(get: { session.project.storyline?.enabled == true },set: { session.setMagnetic($0) })).toggleStyle(.button).help("Pack the primary storyline and move connected clips with their anchors")
                Toggle(isOn: $session.snapping) { Image(systemName: "point.topleft.down.curvedto.point.bottomright.up") }.toggleStyle(.button).help("Snapping (\(shortcuts.label(.snapping)))")
                Menu { Button("Video Track") { session.perform(.addTrack(.video)) }; Button("Audio Track") { session.perform(.addTrack(.audio)) } } label: { Image(systemName: "plus") }.menuStyle(.borderlessButton).frame(width: 24)
                Button { session.split() } label: { Image(systemName: "scissors") }.buttonStyle(.plain).help("Split at playhead (⌘B)")
                Spacer()
                TimelineDragHint(drag: session.timelineDrag)
                Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
                Slider(value: $session.pointsPerSecond, in: 10...240).frame(width: 100).help("Timeline zoom")
                Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary)
            }.controlSize(.small).padding(.horizontal,12).frame(height: 32).background(EditorStyle.panel)
            Divider()
            ScrollView(.vertical) {
                HStack(alignment: .top,spacing: 0) {
                    VStack(spacing: 0) {
                        Text("Tracks").font(.system(size: 10)).foregroundStyle(.secondary).padding(.leading,10).frame(width: headerWidth,height: 28,alignment: .leading)
                        Color.clear.frame(height: leadingSpace)
                        ForEach(visibleTracks) { track in TrackHeader(session: session, track: track).frame(width: headerWidth,height: laneHeight) }
                        Color.clear.frame(height: trailingSpace)
                    }.frame(width: headerWidth).background(EditorStyle.panel)
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
                        .coordinateSpace(name: "timelineContent")
                        .overlay(alignment: .topLeading) { TimelineDragOverlay(drag: session.timelineDrag,frameRate: session.fps,pointsPerSecond: session.pointsPerSecond,laneHeight: laneHeight,visibleRows: visibleRows,visibleRange: (scrollOffset - 200)...(scrollOffset + viewportWidth + 200)) }
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
        }.background(EditorStyle.canvas)
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
        }.frame(width: contentWidth,height: 28).background(EditorStyle.panel).contentShape(Rectangle())
            .contextMenu {
                Button("Add Marker at Playhead") { session.perform(.marker(.init(frame: session.playhead,name: "Marker"))) }
                ForEach(session.project.markers) { marker in
                    Menu("\(marker.name) · \(session.fps.timecode(marker.frame))") {
                        Button("Go to Marker") { session.closeSource(); session.pause(); session.seek(marker.frame) }
                        Button("Delete Marker") { session.perform(.removeMarker(marker.id)) }
                    }
                }
                Divider()
                Toggle("Snapping",isOn: $session.snapping)
            }
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in session.closeSource(); NSApp.keyWindow?.makeFirstResponder(nil); session.pause(); session.seek(session.fps.frames(value.location.x / session.pointsPerSecond)) })
    }
}

private struct TrackHeader: View {
    @ObservedObject var session: EditorSession
    let track: TimelineTrack
    var body: some View {
        VStack(alignment: .leading,spacing: 4) {
            HStack(spacing: 5) {
                Text(track.name).font(.system(size: 10)).lineLimit(1).truncationMode(.tail)
                if session.project.storyline?.trackID == track.id {
                    Image(systemName: "link").font(.system(size: 9)).foregroundStyle(.secondary).help("Primary storyline")
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 2) {
                trackButton("Lock track",symbol: track.locked ? "lock.fill" : "lock.open",active: track.locked) { update(locked: !track.locked) }
                if track.kind == .video {
                    trackButton("Hide video",symbol: track.hidden ? "eye.slash" : "eye",active: track.hidden) { update(hidden: !track.hidden) }
                }
                trackButton("Mute track",symbol: track.muted ? "speaker.slash.fill" : "speaker.wave.2",active: track.muted) { update(muted: !track.muted) }
                Button { update(solo: !track.solo) } label: {
                    Text("S").font(.system(size: 10,weight: track.solo ? .semibold : .regular))
                        .frame(width: 22,height: 20).contentShape(Rectangle())
                }.foregroundStyle(track.solo ? Color.orange : Color.secondary)
                    .help("Solo track audio").accessibilityLabel("Solo track audio").accessibilityValue(track.solo ? "On" : "Off")
            }.buttonStyle(.plain)
        }.padding(.horizontal,10).padding(.top,8).frame(maxWidth: .infinity,maxHeight: .infinity,alignment: .topLeading)
            .background(session.selectedTrack == track.id ? Color.primary.opacity(0.06) : .clear)
            .contentShape(Rectangle()).onTapGesture { session.selectedTrack = track.id }
            .contextMenu {
                TrackContextMenu(session: session,track: track)
            }
            .overlay(alignment: .bottom) { Divider() }
    }
    private func trackButton(_ title: String,symbol: String,active: Bool,action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10))
                .frame(width: 22,height: 20).contentShape(Rectangle())
        }.foregroundStyle(active ? Color.orange : Color.secondary)
            .help(title).accessibilityLabel(title).accessibilityValue(active ? "On" : "Off")
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
        GeometryReader { geometry in
            let x = frameRate.seconds(transport.playhead) * pointsPerSecond
            // Keep the indicator distinct from the panel divider without an accent-colored rail.
            Path { path in
                path.move(to: CGPoint(x: x + 0.5,y: 9))
                path.addLine(to: CGPoint(x: x + 0.5,y: geometry.size.height))
            }.stroke(Color.primary.opacity(0.6),lineWidth: 1)
            Path { path in
                path.move(to: CGPoint(x: x - 4,y: 0))
                path.addLine(to: CGPoint(x: x + 5,y: 0))
                path.addLine(to: CGPoint(x: x + 5,y: 5))
                path.addLine(to: CGPoint(x: x + 0.5,y: 10))
                path.addLine(to: CGPoint(x: x - 4,y: 5))
                path.closeSubpath()
            }.fill(Color.primary.opacity(0.8))
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
