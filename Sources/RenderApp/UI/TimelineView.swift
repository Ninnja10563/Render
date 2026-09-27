import SwiftUI
import UniformTypeIdentifiers
import RenderCore

struct TimelineView: View {
    @ObservedObject var session: EditorSession
    private let headerWidth: CGFloat = 148
    private let laneHeight: CGFloat = 70
    var contentWidth: CGFloat { max(1000,session.fps.seconds(session.project.duration) * session.pointsPerSecond + 300) }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text("TIMELINE").font(.system(size: 10,weight: .semibold)).foregroundStyle(.secondary)
                Picker("Tool", selection: $session.tool) {
                    Image(systemName: "cursorarrow").tag(EditingTool.select)
                    Image(systemName: "scissors").tag(EditingTool.blade)
                    Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right").tag(EditingTool.trim)
                }.pickerStyle(.segmented).frame(width: 110).labelsHidden().help("Selection (A), Blade (B), Trim (T)")
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
                        ForEach(session.project.tracks) { track in TrackHeader(session: session, track: track).frame(width: headerWidth,height: laneHeight) }
                    }.frame(width: headerWidth)
                    Divider()
                    ScrollView(.horizontal) {
                        VStack(spacing: 0) {
                            ruler
                            ForEach(session.project.tracks) { track in
                                ZStack(alignment: .topLeading) {
                                    Rectangle().fill(session.selectedTrack == track.id ? Color.accentColor.opacity(0.035) : Color.primary.opacity(0.018))
                                        .onTapGesture { session.selectedTrack = track.id; session.selection = [] }
                                    ForEach(track.clips) { clip in
                                        ClipTile(session: session, clip: clip, track: track)
                                            .frame(width: max(3,session.fps.seconds(clip.duration) * session.pointsPerSecond),height: laneHeight - 10)
                                            .offset(x: session.fps.seconds(clip.start) * session.pointsPerSecond,y: 5)
                                    }
                                    Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1).offset(y: laneHeight - 1)
                                }.frame(width: contentWidth,height: laneHeight)
                                .onDrop(of: [.text], isTargeted: nil) { providers,location in
                                    guard let provider = providers.first, !track.locked else { return false }
                                    _ = provider.loadObject(ofClass: String.self) { value,_ in
                                        guard let value, let asset = UUID(uuidString: value) else { return }
                                        Task { @MainActor in session.perform(.append(asset: asset,track: track.id,at: session.snap(session.fps.frames(location.x / session.pointsPerSecond)))) }
                                    }
                                    return true
                                }
                            }
                        }
                        .overlay(alignment: .topLeading) {
                            Rectangle().fill(Color.accentColor).frame(width: 1.5).offset(x: session.fps.seconds(session.playhead) * session.pointsPerSecond).allowsHitTesting(false)
                        }
                    }
                }
            }
        }.background(Color(nsColor: .underPageBackgroundColor))
    }
    private var ruler: some View {
        Canvas { context,size in
            let seconds = contentWidth / session.pointsPerSecond
            let step = session.pointsPerSecond < 30 ? 5 : (session.pointsPerSecond < 80 ? 2 : 1)
            for second in stride(from: 0, through: Int(seconds), by: step) {
                let x = Double(second) * session.pointsPerSecond
                var path = Path(); path.move(to: CGPoint(x: x,y: 20)); path.addLine(to: CGPoint(x: x,y: 28))
                context.stroke(path,with: .color(.secondary.opacity(0.5)),lineWidth: 1)
                context.draw(Text(session.fps.timecode(session.fps.frames(Double(second)))).font(.system(size: 9,design: .monospaced)).foregroundColor(.secondary),at: CGPoint(x: x + 5,y: 10),anchor: .leading)
            }
            for marker in session.project.markers {
                let x = session.fps.seconds(marker.frame) * session.pointsPerSecond
                context.fill(Path(CGRect(x: x - 2,y: 18,width: 5,height: 9)),with: .color(.orange))
            }
        }.frame(width: contentWidth,height: 28).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in session.pause(); session.seek(session.fps.frames(value.location.x / session.pointsPerSecond)) })
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
            .overlay(alignment: .bottom) { Divider() }
    }
    func update(locked: Bool? = nil, hidden: Bool? = nil, muted: Bool? = nil, solo: Bool? = nil) {
        session.perform(.trackState(track: track.id,locked: locked ?? track.locked,hidden: hidden ?? track.hidden,muted: muted ?? track.muted,solo: solo ?? track.solo))
    }
}

private struct ClipTile: View {
    @ObservedObject var session: EditorSession
    let clip: TimelineClip
    let track: TimelineTrack
    @State private var dragFrames: Int64 = 0
    var selected: Bool { session.selection.contains(clip.id) }
    var tint: Color { track.kind == .audio ? Color(red: 0.24,green: 0.43,blue: 0.36) : Color(red: 0.23,green: 0.36,blue: 0.49) }
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 3).fill(tint.opacity(track.hidden || track.muted ? 0.5 : 1))
                if track.kind == .video, let image = session.thumbnails[clip.assetID], geometry.size.width > 34 {
                    Image(nsImage: image).resizable().scaledToFill().frame(width: min(90,geometry.size.width),height: 37).clipped().offset(y: 22).opacity(0.8)
                }
                if let peaks = session.waveforms[clip.assetID], let asset = session.project.assets.first(where: { $0.id == clip.assetID }) {
                    Canvas { context,size in
                        var path = Path()
                        for x in stride(from: 0.0,to: size.width,by: 2) {
                            let second = clip.sourceIn + (x / size.width) * session.fps.seconds(clip.duration) * clip.speed
                            let index = min(peaks.count - 1,max(0,Int(second / asset.duration * Double(peaks.count))))
                            guard index >= 0 else { continue }
                            let height = max(1,CGFloat(peaks[index]) * size.height)
                            path.move(to: CGPoint(x: x,y: (size.height - height) / 2)); path.addLine(to: CGPoint(x: x,y: (size.height + height) / 2))
                        }
                        context.stroke(path,with: .color(.white.opacity(0.65)),lineWidth: 1)
                    }.frame(height: track.kind == .audio ? 33 : 16).offset(y: track.kind == .audio ? 24 : 43)
                }
                Text(clip.name).font(.system(size: 10,weight: .medium)).foregroundStyle(.white).lineLimit(1).padding(.horizontal,7).frame(height: 22).frame(maxWidth: .infinity,alignment: .leading).background(.black.opacity(0.15))
                if selected && session.tool != .blade && geometry.size.width > 18 {
                    HStack {
                        trimHandle(.leading)
                        Spacer(minLength: 0)
                        trimHandle(.trailing)
                    }
                }
            }.clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay { RoundedRectangle(cornerRadius: 3).strokeBorder(selected ? Color.accentColor : .white.opacity(0.12),lineWidth: selected ? 2 : 0.5) }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 3).onChanged { value in
                    guard !track.locked, session.tool == .select else { return }
                    if !selected { session.selectClip(clip.id) }
                    let proposed = clip.start + session.fps.frames(value.translation.width / session.pointsPerSecond)
                    dragFrames = session.snap(proposed,excluding: session.selection) - clip.start
                    session.movePreview = dragFrames
                }.onEnded { _ in
                    if dragFrames != 0 { session.perform(.move(clips: session.selection,delta: dragFrames)) }
                    dragFrames = 0; session.movePreview = 0
                })
                .onTapGesture { location in
                    if session.tool == .blade { session.perform(.split(clips: [clip.id],at: clip.start + session.fps.frames(location.x / session.pointsPerSecond))) }
                    else { session.selectClip(clip.id,extend: NSEvent.modifierFlags.contains(.shift) || NSEvent.modifierFlags.contains(.command)) }
                }
                .contextMenu {
                    Button("Split at Playhead") { session.perform(.split(clips: [clip.id],at: session.playhead)) }
                    Menu("Move to Track") {
                        ForEach(session.project.tracks.filter { $0.kind == track.kind && $0.id != track.id && !$0.locked }) { target in
                            Button(target.name) { session.perform(.moveToTrack(clip: clip.id,track: target.id,at: clip.start)) }
                        }
                    }
                    Button("Delete") { session.perform(.delete(clips: [clip.id],ripple: false)) }
                    Button("Ripple Delete") { session.perform(.delete(clips: [clip.id],ripple: true)) }
                }
                .offset(x: session.fps.seconds(selected ? session.movePreview : 0) * session.pointsPerSecond)
        }.help("\(clip.name) · \(session.fps.timecode(clip.duration))\(track.locked ? " · Locked" : "")")
    }
    func trimHandle(_ edge: TrimEdge) -> some View {
        Rectangle().fill(Color.accentColor.opacity(0.75)).frame(width: 5)
            .gesture(DragGesture(minimumDistance: 2).onEnded { value in
                let original = edge == .leading ? clip.start : clip.end
                let target = session.snap(original + session.fps.frames(value.translation.width / session.pointsPerSecond),excluding: [clip.id])
                session.perform(.trim(clip: clip.id,edge: edge,to: target))
            })
            .help(edge == .leading ? "Trim clip start" : "Trim clip end")
    }
}
