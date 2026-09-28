import SwiftUI
import RenderCore

struct ClipTile: View {
    @ObservedObject var session: EditorSession
    let clip: TimelineClip
    let track: TimelineTrack
    let visibleRange: ClosedRange<CGFloat>
    @ObservedObject private var drag: TimelineDragState
    init(session: EditorSession,clip: TimelineClip,track: TimelineTrack,visibleRange: ClosedRange<CGFloat>) {
        self.session = session; self.clip = clip; self.track = track; self.visibleRange = visibleRange; drag = session.timelineDrag
    }
    @State private var beganSelectionDrag = false
    @State private var dragFrames: Int64 = 0
    @State private var trimDelta: Int64 = 0
    @State private var trimEdge: TrimEdge = .trailing
    var selected: Bool { session.selection.contains(clip.id) }
    var tint: Color { clip.isGap == true ? Color.gray : track.kind == .audio ? Color(red: 0.24,green: 0.43,blue: 0.36) : Color(red: 0.23,green: 0.36,blue: 0.49) }
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 3).fill(tint.opacity(track.hidden || track.muted ? 0.5 : 1))
                if track.kind == .video, let assetID = clip.assetID, let media = session.project.assets.first(where: { $0.id == assetID }), geometry.size.width > 34 {
                    FilmstripView(media: media,clip: clip,library: session.library,poster: session.thumbnails[assetID],pointsPerSecond: session.pointsPerSecond,frameRate: session.fps,visibleRange: visibleRange,width: geometry.size.width,mode: session.playbackMode)
                        .offset(y: 22).opacity(0.8)
                }
                if let assetID = clip.assetID, let peaks = session.waveforms[assetID], let asset = session.project.assets.first(where: { $0.id == clip.assetID }) {
                    let clipOrigin = session.fps.seconds(clip.start) * session.pointsPerSecond
                    let localStart = max(0,visibleRange.lowerBound - clipOrigin)
                    let drawWidth = max(0,min(geometry.size.width,visibleRange.upperBound - clipOrigin) - localStart)
                    Canvas { context,size in
                        var path = Path()
                        for x in stride(from: 0.0,to: size.width,by: 2) {
                            let second = clip.sourceIn + ((localStart + x) / max(1,geometry.size.width)) * session.fps.seconds(clip.duration) * clip.speed
                            let index = min(peaks.count - 1,max(0,Int(second / asset.duration * Double(peaks.count))))
                            guard index >= 0 else { continue }
                            let height = max(1,CGFloat(peaks[index]) * size.height)
                            path.move(to: CGPoint(x: x,y: (size.height - height) / 2)); path.addLine(to: CGPoint(x: x,y: (size.height + height) / 2))
                        }
                        context.stroke(path,with: .color(.white.opacity(0.65)),lineWidth: 1)
                    }.frame(width: drawWidth,height: track.kind == .audio ? 33 : 16).offset(x: localStart,y: track.kind == .audio ? 24 : 43)
                }
                if clip.compoundID != nil {
                    Label("Compound",systemImage: "square.stack.3d.up").font(.system(size: 10)).foregroundStyle(.white.opacity(0.7)).padding(.horizontal,8).offset(y: 31)
                }
                Text((clip.connection != nil ? "↳ " : "") + clip.name).font(.system(size: 10,weight: .medium)).foregroundStyle(.white).lineLimit(1).padding(.horizontal,7).frame(height: 22).frame(maxWidth: .infinity,alignment: .leading).background(.black.opacity(0.15))
                if selected && session.tool != .blade && geometry.size.width > 18 {
                    HStack {
                        trimHandle(.leading)
                        Spacer(minLength: 0)
                        trimHandle(.trailing)
                    }
                }
            }.frame(width: max(3,geometry.size.width + session.fps.seconds(trimEdge == .leading ? -trimDelta : trimDelta) * session.pointsPerSecond),height: geometry.size.height)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay { RoundedRectangle(cornerRadius: 3).strokeBorder(selected ? Color.accentColor : .white.opacity(0.12),lineWidth: selected ? 2 : 0.5) }
                .overlay(alignment: .bottomTrailing) {
                    if let transition = clip.transition {
                        Image(systemName: "arrow.left.arrow.right").font(.system(size: 9)).foregroundStyle(.white)
                            .frame(width: max(12,session.fps.seconds(transition.duration / 2) * session.pointsPerSecond),height: 14)
                            .background(Color.gray.opacity(0.85)).padding(2).help("\(transition.kind.label) · \(session.fps.seconds(transition.duration).formatted()) seconds")
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if dragFrames != 0, session.tool != .select {
                        Text("\(session.tool.rawValue) \(dragFrames > 0 ? "+" : "")\(dragFrames)f")
                            .font(.system(size: 9,weight: .semibold,design: .monospaced)).padding(4).background(.black.opacity(0.8)).foregroundStyle(.white)
                    }
                }
                .contentShape(Rectangle())
                .opacity(drag.active && selected ? 0.25 : 1)
                .gesture(DragGesture(minimumDistance: 3,coordinateSpace: .named("timelineContent")).onChanged { value in
                    guard !track.locked, session.tool != .blade else { return }
                    if !selected { session.selectClip(clip.id) }
                    let delta = session.fps.frames(value.translation.width / session.pointsPerSecond)
                    if session.tool == .select {
                        if !beganSelectionDrag {
                            session.pause(); NSApp.keyWindow?.makeFirstResponder(nil)
                            do { try drag.begin(project: session.project,selection: session.selection); beganSelectionDrag = true }
                            catch { session.report(error); return }
                        }
                        let frames = session.snap(clip.start + delta,excluding: session.selection) - clip.start
                        let offset = Int((value.translation.height / 70).rounded())
                        drag.update(delta: frames,trackOffset: offset)
                    } else {
                        dragFrames = delta
                        if session.tool == .slide { session.movePreview = delta }
                    }
                }.onEnded { _ in
                    if beganSelectionDrag {
                        do { if let command = try drag.finish() { session.perform(command) } } catch { session.report(error) }
                        beganSelectionDrag = false
                    } else if dragFrames != 0 {
                        switch session.tool {
                        case .select: session.perform(.move(clips: session.selection,delta: dragFrames))
                        case .trim: session.perform(.trim(clip: clip.id,edge: .trailing,to: clip.end + dragFrames))
                        case .slip: session.perform(.slip(clip: clip.id,delta: dragFrames))
                        case .slide: session.perform(.slide(clip: clip.id,delta: dragFrames))
                        case .roll: session.perform(.roll(clip: clip.id,boundary: clip.end + dragFrames))
                        case .ripple: session.perform(.rippleTrim(clip: clip.id,edge: .trailing,to: clip.end + dragFrames))
                        default: break
                        }
                    }
                    dragFrames = 0; session.movePreview = 0
                })
                .onTapGesture { location in
                    if session.tool == .blade { session.perform(.split(clips: [clip.id],at: clip.start + session.fps.frames(location.x / session.pointsPerSecond))) }
                    else { session.selectClip(clip.id,extend: NSEvent.modifierFlags.contains(.shift) || NSEvent.modifierFlags.contains(.command)) }
                }
                .contextMenu {
                    if let id = clip.compoundID {
                        Button("Open Compound Timeline") { session.openCompound(id) }
                        Button("Break Apart Compound") { session.perform(.breakApart(clip.id)) }
                        Divider()
                    }
                    Button("Create Compound Clip") { if !selected { session.selectClip(clip.id) }; session.createCompound() }

                    Button("Split at Playhead") { session.perform(.split(clips: [clip.id],at: session.playhead)) }
                    Menu("Move to Track") {
                        ForEach(session.project.tracks.filter { $0.kind == track.kind && $0.id != track.id && !$0.locked }) { target in
                            Button(target.name) { session.perform(.moveToTrack(clip: clip.id,track: target.id,at: clip.start)) }
                        }
                    }
                    Button("Detach Audio") { session.perform(.detachAudio(clip: clip.id)) }
                        .disabled(session.project.assets.first(where: { $0.id == clip.assetID })?.kind != .video || (session.project.assets.first(where: { $0.id == clip.assetID })?.audioChannels ?? 0) == 0)
                    Button("Delete") { session.perform(.delete(clips: [clip.id],ripple: false)) }
                    Button("Ripple Delete") { session.perform(.delete(clips: [clip.id],ripple: true)) }
                }
                .offset(x: session.fps.seconds((selected ? session.movePreview : 0) + (trimEdge == .leading && session.tool != .ripple ? trimDelta : 0)) * session.pointsPerSecond)
        }.onDisappear { if beganSelectionDrag { drag.cancel(); beganSelectionDrag = false } }
            .help("\(clip.name) · \(session.fps.timecode(clip.duration))\(track.locked ? " · Locked" : "")")
    }
    func trimHandle(_ edge: TrimEdge) -> some View {
        Rectangle().fill(Color.accentColor.opacity(0.75)).frame(width: 5)
            .gesture(DragGesture(minimumDistance: 2).onChanged { value in
                guard !track.locked else { return }
                trimEdge = edge
                trimDelta = session.fps.frames(value.translation.width / session.pointsPerSecond)
            }.onEnded { value in
                defer { trimDelta = 0 }
                guard !track.locked else { return }
                let original = edge == .leading ? clip.start : clip.end
                let target = session.snap(original + session.fps.frames(value.translation.width / session.pointsPerSecond),excluding: [clip.id])
                if session.tool == .ripple { session.perform(.rippleTrim(clip: clip.id,edge: edge,to: target)) }
                else if session.tool == .roll {
                    let leftID = edge == .trailing ? clip.id : track.clips.first(where: { $0.end == clip.start && $0.id != clip.id })?.id
                    if let leftID { session.perform(.roll(clip: leftID,boundary: target)) }
                    else { session.errorMessage = "Roll needs an adjacent clip at this edge." }
                } else { session.perform(.trim(clip: clip.id,edge: edge,to: target)) }
            })
            .help(edge == .leading ? "Trim clip start" : "Trim clip end")
    }
}
