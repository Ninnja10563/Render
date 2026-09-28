import SwiftUI
import RenderCore

struct KeyframeEditorView: View {
    @ObservedObject var session: EditorSession
    let clip: TimelineClip
    @Binding var clipboard: [Keyframe]
    @State private var target = AnimationTarget.property("opacity")
    @State private var selected: Set<UUID> = []

    private var curve: AnimationCurve { (try? target.curve(in: clip)) ?? AnimationCurve() }
    private var frame: Int64 { max(0,min(clip.duration - 1,session.playhead - clip.start)) + clip.animationOffset }
    private var visibleKeys: [Keyframe] { curve.keys.sorted { $0.frame < $1.frame } }
    private let propertyNames = ["x","y","scale","scaleX","scaleY","anchorX","anchorY","rotation","opacity","cropLeft","cropRight","cropTop","cropBottom","volume"]
    private let propertyLabels = ["x": "Position X","y": "Position Y","scale": "Scale","scaleX": "Scale X","scaleY": "Scale Y","anchorX": "Anchor X","anchorY": "Anchor Y","rotation": "Rotation","opacity": "Opacity","cropLeft": "Crop Left","cropRight": "Crop Right","cropTop": "Crop Top","cropBottom": "Crop Bottom","volume": "Volume"]
    private var availableTargets: [AnimationTarget] {
        propertyNames.map(AnimationTarget.property) + clip.effects.map { .effect($0.id) }
    }
    var body: some View {
        VStack(alignment: .leading,spacing: 8) {
            Picker("Parameter",selection: $target) {
                ForEach(propertyNames,id: \.self) { key in Text(propertyLabels[key] ?? key).tag(AnimationTarget.property(key)) }
                ForEach(Array(clip.effects.enumerated()),id: \.element.id) { index,effect in
                    Text("\(index + 1). \(effect.kind.label)").tag(AnimationTarget.effect(effect.id))
                }
            }.font(.system(size: 10))
            HStack(spacing: 10) {
                Button { navigate(previous: true) } label: { Image(systemName: "backward.end") }.help("Previous keyframe")
                    .disabled(!visibleKeys.contains { $0.frame < frame && $0.frame >= clip.animationOffset })
                Button {
                    if let value = try? target.value(in: clip,at: frame) { edit(.set(frame: frame,value: value)) }
                } label: { Label("Add",systemImage: "diamond") }.help("Add a keyframe at the playhead")
                Button { navigate(previous: false) } label: { Image(systemName: "forward.end") }.help("Next keyframe")
                    .disabled(!visibleKeys.contains { $0.frame > frame && $0.frame < clip.animationOffset + clip.duration })
                Spacer(minLength: 0)
                Text("\(curve.keys.count) keys").foregroundStyle(.secondary)
            }.font(.system(size: 10)).buttonStyle(.plain)
            if !curve.keys.isEmpty {
                AnimationCurvePlot(curve: curve,offset: clip.animationOffset,duration: clip.duration,playhead: frame) { local in session.seek(clip.start + local) }
                Text("Frame within clip · value · outgoing curve").font(.system(size: 9)).foregroundStyle(.secondary)
                // A bounded viewport keeps long automation curves inexpensive to inspect.
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(visibleKeys) { key in
                            KeyframeRow(key: key,offset: clip.animationOffset,duration: clip.duration,selected: selected.contains(key.id),select: {
                                if selected.contains(key.id) { selected.remove(key.id) } else { selected.insert(key.id) }
                            },seek: { session.seek(clip.start + key.frame - clip.animationOffset) },move: { local in
                                guard local >= 0, local < clip.duration else { session.errorMessage = "Place the keyframe within the visible clip."; return }
                                edit(.move(key: key.id,to: clip.animationOffset + local))
                            },setValue: { edit(.set(frame: key.frame,value: $0)) },interpolate: { edit(.interpolation([key.id],$0)) })
                        }
                    }
                }.frame(maxHeight: 200)
            }
            HStack(spacing: 8) {
                Button("Copy") { clipboard = visibleKeys.filter { selected.isEmpty || selected.contains($0.id) } }.disabled(curve.keys.isEmpty)
                Button("Paste") {
                    guard let first = clipboard.map(\.frame).min(), let last = clipboard.map(\.frame).max(), last - first < clip.animationOffset + clip.duration - frame else {
                        session.errorMessage = "The copied animation does not fit between the playhead and the end of this clip."; return
                    }
                    edit(.paste(clipboard,at: frame))
                }.disabled(clipboard.isEmpty)
                Spacer(minLength: 0)
                Button("Delete") { edit(.remove(selected)); selected.removeAll() }.disabled(selected.isEmpty)
            }.controlSize(.mini)
            Text("Copy uses selected keys, or all keys when none are selected. Paste aligns the first key to the playhead. Dimmed keys lie outside the trimmed clip.")
                .font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .onChange(of: target) { _,_ in selected.removeAll() }
        .onChange(of: clip.id) { _,_ in selected.removeAll(); if !availableTargets.contains(target) { target = .property("opacity") } }
        .onChange(of: availableTargets) { _,targets in if !targets.contains(target) { target = .property("opacity") } }
    }
    private func edit(_ edit: AnimationEdit) { session.perform(.animation(clip: clip.id,target: target,edit: edit)) }
    private func navigate(previous: Bool) {
        let visible = visibleKeys.filter { $0.frame >= clip.animationOffset && $0.frame < clip.animationOffset + clip.duration }
        let key = previous ? visible.last(where: { $0.frame < frame }) : visible.first(where: { $0.frame > frame })
        if let key { session.seek(clip.start + key.frame - clip.animationOffset) }
    }
}

private struct KeyframeRow: View {
    let key: Keyframe
    let offset: Int64
    let duration: Int64
    let selected: Bool
    let select: () -> Void
    let seek: () -> Void
    let move: (Int64) -> Void
    let setValue: (Double) -> Void
    let interpolate: (Interpolation) -> Void
    @FocusState private var focused: Field?
    private enum Field { case frame, value }
    @State private var draftFrame = ""
    @State private var draftValue = ""
    private var visible: Bool { key.frame >= offset && key.frame < offset + duration }
    var body: some View {
        HStack(spacing: 5) {
            Button(action: select) { Image(systemName: selected ? "checkmark.square.fill" : "square") }.buttonStyle(.plain).help("Select keyframe")
            TextField("Frame",text: $draftFrame)
                .frame(width: 42).focused($focused,equals: .frame).onSubmit { _ = commit(.frame) }.help("Frame relative to the clip start")
            TextField("Value",text: $draftValue)
                .frame(width: 43).focused($focused,equals: .value).onSubmit { _ = commit(.value) }
            Picker("Interpolation",selection: Binding(get: { key.interpolation },set: interpolate)) {
                Text("Linear").tag(Interpolation.linear)
                Text("Ease In").tag(Interpolation.easeIn)
                Text("Ease Out").tag(Interpolation.easeOut)
                Text("Ease In/Out").tag(Interpolation.easeInOut)
                Text("Hold").tag(Interpolation.hold)
            }.labelsHidden().frame(maxWidth: .infinity)
            Button(action: seek) { Image(systemName: "scope") }.buttonStyle(.plain).disabled(!visible).help("Go to keyframe")
        }.font(.system(size: 10)).controlSize(.mini).opacity(visible ? 1 : 0.55)
            .onAppear { refresh() }.onChange(of: key) { _,_ in refresh() }.onChange(of: offset) { _,_ in refresh() }
            .onChange(of: focused) { old,_ in _ = commit(old) }
            .onReceive(NotificationCenter.default.publisher(for: .renderCommitInspector)) { note in
                let invalid = Int64(draftFrame.trimmingCharacters(in: .whitespacesAndNewlines)) == nil || (try? Double(draftValue,format: .number.grouping(.never))).map { !$0.isFinite } != false
                if invalid { (note.object as? InspectorCommitRequest)?.error = "Correct the invalid keyframe field before saving." }
                else if let error = commit(focused) { (note.object as? InspectorCommitRequest)?.error = error }
            }
    }
    private func commit(_ field: Field?) -> String? {
        switch field {
        case .frame:
            guard let frame = Int64(draftFrame.trimmingCharacters(in: .whitespacesAndNewlines)) else { return "Enter a valid keyframe position before saving." }
            if frame != key.frame - offset { move(frame) }
        case .value:
            guard let value = try? Double(draftValue,format: .number.grouping(.never)), value.isFinite else { return "Enter a valid keyframe value before saving." }
            if draftValue != formattedValue { setValue(value) }
        case nil: break
        }
        return nil
    }
    private var formattedValue: String { key.value.formatted(.number.grouping(.never).precision(.fractionLength(0...6))) }
    private func refresh() {
        draftFrame = String(key.frame - offset)
        draftValue = formattedValue
    }

}

struct EffectAmountView: View {
    @ObservedObject var session: EditorSession
    let clip: TimelineClip
    let effect: Effect
    private var frame: Int64 { max(0,min(clip.duration - 1,session.playhead - clip.start)) + clip.animationOffset }
    var body: some View {
        HStack(spacing: 7) {
            InspectorNumber(label: "Amount",value: effect.animation.value(at: Double(frame),fallback: effect.amount),range: effect.kind.range,reset: effect.kind.defaultValue) { value in
                if effect.animation.keys.isEmpty {
                    var effects = clip.effects
                    if let index = effects.firstIndex(where: { $0.id == effect.id }) { effects[index].amount = value; session.perform(.effects(clip: clip.id,effects)) }
                } else { session.perform(.animation(clip: clip.id,target: .effect(effect.id),edit: .set(frame: frame,value: value))) }
            }
            Button {
                let ids = Set(effect.animation.keys.filter { $0.frame == frame }.map(\.id))
                let edit: AnimationEdit = ids.isEmpty ? .set(frame: frame,value: effect.animation.value(at: Double(frame),fallback: effect.amount)) : .remove(ids)
                session.perform(.animation(clip: clip.id,target: .effect(effect.id),edit: edit))
            } label: { Image(systemName: effect.animation.keys.contains { $0.frame == frame } ? "diamond.fill" : "diamond") }
                .buttonStyle(.plain).help("Add / remove effect keyframe")
        }
    }
}

private struct AnimationCurvePlot: View {
    let curve: AnimationCurve
    let offset: Int64
    let duration: Int64
    let playhead: Int64
    let seek: (Int64) -> Void
    var body: some View {
        GeometryReader { geometry in
            Canvas { context,size in
                let lower = curve.keys.map(\.value).min() ?? 0
                let upper = curve.keys.map(\.value).max() ?? 1
                let span = max(0.001,upper - lower)
                func point(_ frame: Double,_ value: Double) -> CGPoint {
                    CGPoint(x: (frame - Double(offset)) / Double(max(1,duration - 1)) * size.width,
                            y: size.height - 6 - (value - lower) / span * (size.height - 12))
                }
                var line = Path()
                for step in 0...128 {
                    let frame = Double(offset) + Double(max(1,duration - 1)) * Double(step) / 128
                    let p = point(frame,curve.value(at: frame,fallback: 0))
                    if step == 0 { line.move(to: p) } else { line.addLine(to: p) }
                }
                context.stroke(line,with: .color(.accentColor),lineWidth: 1.5)
                for key in curve.keys where key.frame >= offset && key.frame < offset + duration {
                    let p = point(Double(key.frame),key.value)
                    context.fill(Path(ellipseIn: CGRect(x: p.x - 2.5,y: p.y - 2.5,width: 5,height: 5)),with: .color(.primary))
                }
                let x = point(Double(playhead),lower).x
                var cursor = Path(); cursor.move(to: CGPoint(x: x,y: 0)); cursor.addLine(to: CGPoint(x: x,y: size.height))
                context.stroke(cursor,with: .color(.secondary),lineWidth: 1)
            }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let ratio = max(0,min(1,value.location.x / max(1,geometry.size.width)))
                seek(Int64((ratio * Double(max(0,duration - 1))).rounded()))
            })
        }.frame(height: 64).accessibilityLabel("Animation curve. Drag to scrub within the clip.")
    }
}
