import SwiftUI
import RenderCore

struct InspectorView: View {
    @ObservedObject var session: EditorSession
    @State private var keyframeClipboard: [Keyframe] = []
    @ObservedObject private var transport: TransportState
    init(session: EditorSession) { self.session = session; transport = session.transport }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("INSPECTOR").font(.system(size: 10,weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                if session.selectedClip != nil { Image(systemName: "slider.horizontal.3").foregroundStyle(.secondary) }
            }.padding(.horizontal,12).frame(height: 32)
            Divider()
            ScrollView {
                if let clip = session.selectedClip {
                    VStack(alignment: .leading,spacing: 18) {
                        VStack(alignment: .leading,spacing: 5) {
                            Text(clip.name).font(.system(size: 12,weight: .semibold)).lineLimit(2)
                            Text("\(session.fps.timecode(clip.duration)) · \(Int(clip.speed * 100))% speed").font(.system(size: 10,design: .monospaced)).foregroundStyle(.secondary)
                        }
                        if let title = clip.title { TitleInspectorView(session: session,clip: clip,title: title) }
                        if isVisual(clip) {
                        inspectorSection("Transform") {
                            property("Position X",key: "x",range: -1920...1920,reset: 0,clip: clip)
                            property("Position Y",key: "y",range: -1080...1080,reset: 0,clip: clip)
                            property("Scale (%)",key: "scale",range: 0.01...4,reset: 1,clip: clip,displayScale: 100)
                            property("Scale X (%)",key: "scaleX",range: 0.01...4,reset: 1,clip: clip,displayScale: 100)
                            property("Scale Y (%)",key: "scaleY",range: 0.01...4,reset: 1,clip: clip,displayScale: 100)
                            property("Anchor X (%)",key: "anchorX",range: 0...1,reset: 0.5,clip: clip,displayScale: 100)
                            property("Anchor Y (%)",key: "anchorY",range: 0...1,reset: 0.5,clip: clip,displayScale: 100)
                            property("Rotation",key: "rotation",range: -180...180,reset: 0,clip: clip)
                            Toggle("Flip Horizontal",isOn: Binding(get: { clip.properties.geometry?.flipHorizontal ?? false },set: { value in geometry(clip) { $0.flipHorizontal = value } }))
                            Toggle("Flip Vertical",isOn: Binding(get: { clip.properties.geometry?.flipVertical ?? false },set: { value in geometry(clip) { $0.flipVertical = value } }))
                        }
                        inspectorSection("Compositing") {
                            property("Opacity (%)",key: "opacity",range: 0...1,reset: 1,clip: clip,displayScale: 100)
                            Picker("Blend Mode",selection: Binding(get: { clip.properties.geometry?.blend ?? .normal },set: { value in geometry(clip) { $0.blend = value } })) {
                                ForEach(BlendMode.allCases,id: \.self) { mode in Text(mode.label).tag(mode) }
                            }.font(.system(size: 10))
                        }
                        inspectorSection("Crop") {
                            property("Left (%)",key: "cropLeft",range: 0...1,reset: 0,clip: clip,displayScale: 100)
                            property("Right (%)",key: "cropRight",range: 0...1,reset: 0,clip: clip,displayScale: 100)
                            property("Top (%)",key: "cropTop",range: 0...1,reset: 0,clip: clip,displayScale: 100)
                            property("Bottom (%)",key: "cropBottom",range: 0...1,reset: 0,clip: clip,displayScale: 100)
                        }
                        }
                        if hasAudio(clip) {
                        inspectorSection("Audio") {
                            property("Volume",key: "volume",range: 0...4,reset: 1,clip: clip)
                            Toggle("Mute clip",isOn: Binding(get: { clip.properties.muted },set: { value in var p = clip.properties; p.muted = value; session.perform(.properties(clip: clip.id,p)) })).font(.system(size: 11))
                        }
                            AudioFadeInspectorView(session: session,clip: clip)
                        }
                        inspectorSection("Timing") {
                            InspectorNumber(label: "Speed (%)",value: clip.speed * 100,range: 5...1600,reset: 100) { session.perform(.speed(clip: clip.id,$0 / 100)) }
                            HStack {
                                ForEach([25,50,100,200,400],id: \.self) { speed in Button("\(speed)") { session.perform(.speed(clip: clip.id,Double(speed) / 100)) }.font(.system(size: 9)) }
                            }.controlSize(.mini)
                        }
                        if isVisual(clip) {
                        TransitionInspectorView(session: session,clip: clip)
                        inspectorSection("Effects") {
                            ForEach(Array(clip.effects.enumerated()),id: \.element.id) { index,effect in
                                VStack(spacing: 6) {
                                    HStack {
                                        Toggle(effect.kind.label,isOn: Binding(get: { effect.enabled },set: { enabled in changeEffect(clip,index: index) { $0.enabled = enabled } })).font(.system(size: 11))
                                        Spacer(minLength: 0)
                                        Button { changeEffect(clip,index: index) { current in
                                            let identity = current.id; current = Effect(kind: current.kind); current.id = identity
                                        } } label: { Image(systemName: "arrow.counterclockwise") }.help("Reset effect, animation and mask")
                                        Button { var effects = clip.effects; effects.swapAt(index,index - 1); session.perform(.effects(clip: clip.id,effects)) } label: { Image(systemName: "arrow.up") }.disabled(index == 0).help("Move effect earlier")
                                        Button { var effects = clip.effects; effects.remove(at: index); session.perform(.effects(clip: clip.id,effects)) } label: { Image(systemName: "xmark") }.help("Remove effect")
                                    }.buttonStyle(.plain)
                                    EffectAmountView(session: session,clip: clip,effect: effect)
                                    EffectDetailsView(session: session,clip: clip,effect: effect)
                                }.padding(.bottom,4)
                            }
                            Menu { ForEach(EffectKind.allCases,id: \.self) { kind in Button(kind.label) { session.perform(.effects(clip: clip.id,clip.effects + [Effect(kind: kind)])) } } } label: { Label("Add Effect",systemImage: "plus") }
                        }
                        }
                        inspectorSection("Animation") {
                            KeyframeEditorView(session: session,clip: clip,clipboard: $keyframeClipboard)
                        }
                    }.padding(14)
                } else if let media = session.selectedMedia {
                    VStack(alignment: .leading,spacing: 14) {
                        Text(media.name).font(.system(size: 12,weight: .semibold))
                        LabeledContent("Duration",value: session.fps.timecode(session.fps.frames(media.duration)))
                        LabeledContent("Resolution",value: "\(media.width) × \(media.height)")
                        LabeledContent("Frame rate",value: media.frameRate.formatted(.number.precision(.fractionLength(0...3))))
                        LabeledContent("Codec",value: media.codec)
                        LabeledContent("Audio",value: "\(media.audioChannels) channels")
                        Divider()
                        Text(media.url.path).font(.system(size: 10)).foregroundStyle(.secondary).textSelection(.enabled)
                        Button("Relink Media…") { session.relink(media) }
                    }.font(.system(size: 11)).padding(14)
                } else {
                    VStack(alignment: .leading,spacing: 16) {
                        Text(session.selection.count > 1 ? "\(session.selection.count) clips selected" : "Project").font(.system(size: 12,weight: .semibold))
                        Text("Select a clip to edit its transform, audio, speed and effects.").font(.system(size: 11)).foregroundStyle(.secondary)
                        Divider()
                        ProjectSettingsView(session: session)
                        if !session.project.markers.isEmpty {
                            Divider()
                            Text("Markers").font(.system(size: 11,weight: .semibold))
                            ForEach(session.project.markers) { marker in
                                HStack {
                                    Button(marker.name) { session.seek(marker.frame) }.buttonStyle(.plain)
                                    Spacer()
                                    Button { session.perform(.removeMarker(marker.id)) } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                                }.font(.system(size: 10))
                            }
                        }
                    }.padding(14)
                }
            }
        }
    }
    func hasAudio(_ clip: TimelineClip) -> Bool {
        guard let media = session.project.assets.first(where: { $0.id == clip.assetID }) else { return false }
        return media.kind == .audio || media.audioChannels > 0
    }
    func isVisual(_ clip: TimelineClip) -> Bool { session.project.assets.first(where: { $0.id == clip.assetID })?.kind != .audio }
    func property(_ label: String,key: String,range: ClosedRange<Double>,reset: Double,clip: TimelineClip,displayScale: Double = 1) -> some View {
        let frame = max(0,min(clip.duration - 1,session.playhead - clip.start)) + clip.animationOffset
        let keyed = clip.properties.animations[key]?.keys.contains { $0.frame == frame } ?? false
        return HStack(spacing: 7) {
            InspectorNumber(label: label,value: clip.properties.value(key,at: Double(frame)) * displayScale,range: (range.lowerBound * displayScale)...(range.upperBound * displayScale),reset: reset * displayScale) { session.setProperty(key,value: $0 / displayScale,clipID: clip.id) }
            Button { session.toggleKeyframe(key) } label: { Image(systemName: keyed ? "diamond.fill" : "diamond").foregroundStyle(keyed ? Color.accentColor : Color.secondary) }.buttonStyle(.plain).help("Add / remove keyframe")
        }
    }
    func geometry(_ clip: TimelineClip,change: (inout ClipGeometry) -> Void) {
        var p = clip.properties; var geometry = p.geometry ?? ClipGeometry(); change(&geometry); p.geometry = geometry
        session.perform(.properties(clip: clip.id,p))
    }
    func changeEffect(_ clip: TimelineClip,index: Int,change: (inout Effect) -> Void) {
        var effects = clip.effects; change(&effects[index]); session.perform(.effects(clip: clip.id,effects))
    }
    func inspectorSection<Content: View>(_ title: String,@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading,spacing: 10) {
            HStack { Text(title).font(.system(size: 11,weight: .semibold)); Spacer() }
            content()
            Divider()
        }
    }
}

struct InspectorNumber: View {
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    let reset: Double
    let commit: (Double) -> Void
    @State private var draft: Double = 0
    @FocusState private var fieldFocused: Bool
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(label).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                TextField(label,value: $draft,format: .number.precision(.fractionLength(0...2)))
                    .multilineTextAlignment(.trailing).textFieldStyle(.plain).frame(width: 60).focused($fieldFocused)
                    .onSubmit { commit(draft) }
                Button { draft = reset; commit(reset) } label: { Image(systemName: "arrow.counterclockwise").font(.system(size: 9)) }.buttonStyle(.plain).help("Reset \(label)")
            }.font(.system(size: 10))
            Slider(value: Binding(get: { min(range.upperBound,max(range.lowerBound,draft)) },set: { draft = $0 }),in: range,onEditingChanged: { editing in if !editing { commit(draft) } }).controlSize(.mini)
        }.onAppear { draft = value }.onChange(of: value) { _,new in draft = new }
            .onChange(of: fieldFocused) { wasFocused,isFocused in if wasFocused && !isFocused && draft != value { commit(draft) } }
    }
}

private struct ProjectSettingsView: View {
    @ObservedObject var session: EditorSession
    var body: some View {
        VStack(alignment: .leading,spacing: 12) {
            Text("Sequence Settings").font(.system(size: 11,weight: .semibold))
            Picker("Resolution",selection: Binding(get: { session.project.settings.width },set: { width in
                var p = session.project; p.settings.width = width; p.settings.height = width * 9 / 16; session.commit(p,name: "Change Resolution")
            })) {
                Text("720p").tag(1280); Text("1080p").tag(1920); Text("1440p").tag(2560); Text("4K UHD").tag(3840)
            }
            Picker("Frame rate",selection: Binding(get: { session.fps.numerator },set: { numerator in
                var p = session.project; p.settings.frameRate = FrameRate(numerator); session.commit(p,name: "Change Frame Rate")
            })) { ForEach([24,25,30,50,60],id: \.self) { Text("\($0) fps").tag(Int32($0)) } }.disabled(session.project.duration > 0)
            Text("Set the frame rate before adding clips. Timecode is non-drop-frame.").font(.system(size: 10)).foregroundStyle(.secondary)
        }.font(.system(size: 11))
    }
}
