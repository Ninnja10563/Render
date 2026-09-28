import SwiftUI
import AppKit
import RenderCore

struct EffectDetailsView: View {
    @ObservedObject var session: EditorSession
    let clip: TimelineClip
    let effect: Effect
    var body: some View {
        VStack(alignment: .leading,spacing: 8) {
            if effect.kind == .chromaKey {
                ColorPicker("Key colour",selection: Binding(get: {
                    let key = effect.keying ?? ChromaKeySettings()
                    return Color(.sRGB,red: key.red,green: key.green,blue: key.blue,opacity: 1)
                },set: { color in
                    guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                    changeKey { $0.red = rgb.redComponent; $0.green = rgb.greenComponent; $0.blue = rgb.blueComponent }
                }),supportsOpacity: false).font(.system(size: 10))
                Text("Amount controls similarity to the key colour.").font(.system(size: 10)).foregroundStyle(.secondary)
                InspectorNumber(label: "Edge softness",value: (effect.keying ?? ChromaKeySettings()).softness,range: 0...1,reset: 0.1) { value in changeKey { $0.softness = value } }
                InspectorNumber(label: "Spill suppression",value: (effect.keying ?? ChromaKeySettings()).spill,range: 0...1,reset: 0.5) { value in changeKey { $0.spill = value } }
            }
            DisclosureGroup("Effect Mask") {
                Picker("Shape",selection: Binding(get: { effect.mask?.shape.rawValue ?? "none" },set: { value in
                    change { current in
                        if let shape = MaskShape(rawValue: value) { var mask = current.mask ?? EffectMask(); mask.shape = shape; current.mask = mask }
                        else { current.mask = nil }
                    }
                })) {
                    Text("None").tag("none")
                    Text("Rectangle").tag("rectangle"); Text("Ellipse").tag("ellipse"); Text("Polygon").tag("polygon")
                }.font(.system(size: 10))
                if let mask = effect.mask {
                    VStack(spacing: 8) {
                        InspectorNumber(label: "Position X",value: mask.x,range: -1...2,reset: 0.5) { value in changeMask { $0.x = value } }
                        InspectorNumber(label: "Position Y",value: mask.y,range: -1...2,reset: 0.5) { value in changeMask { $0.y = value } }
                        InspectorNumber(label: "Width",value: mask.width,range: 0.001...4,reset: 0.6) { value in changeMask { $0.width = value } }
                        InspectorNumber(label: "Height",value: mask.height,range: 0.001...4,reset: 0.6) { value in changeMask { $0.height = value } }
                        InspectorNumber(label: "Feather",value: mask.feather,range: 0...0.5,reset: 0.02) { value in changeMask { $0.feather = value } }
                        InspectorNumber(label: "Expansion",value: mask.expansion,range: -0.5...0.5,reset: 0) { value in changeMask { $0.expansion = value } }
                        Toggle("Invert mask",isOn: Binding(get: { mask.inverted },set: { value in changeMask { $0.inverted = value } })).font(.system(size: 10))
                        if mask.shape == .polygon {
                            PolygonMaskEditor(points: mask.points) { points in changeMask { $0.points = points } }
                        }
                        Text("Coordinates are relative to the source image. The mask follows the clip transform and limits this effect.")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                        Button("Reset Mask") { change { $0.mask = EffectMask() } }.controlSize(.mini)
                    }
                }
            }.font(.system(size: 10))
        }
    }
    private func change(_ operation: (inout Effect) -> Void) {
        var effects = clip.effects
        guard let index = effects.firstIndex(where: { $0.id == effect.id }) else { return }
        operation(&effects[index]); session.perform(.effects(clip: clip.id,effects))
    }
    private func changeKey(_ operation: (inout ChromaKeySettings) -> Void) {
        change { effect in var key = effect.keying ?? ChromaKeySettings(); operation(&key); effect.keying = key }
    }
    private func changeMask(_ operation: (inout EffectMask) -> Void) {
        change { effect in var mask = effect.mask ?? EffectMask(); operation(&mask); effect.mask = mask }
    }
}

private struct PolygonMaskEditor: View {
    let points: [MaskPoint]
    let commit: ([MaskPoint]) -> Void
    @State private var draft: [MaskPoint]?
    @State private var dragged: Int?
    @State private var selected: Int?
    var body: some View {
        VStack(alignment: .leading,spacing: 6) {
            GeometryReader { geometry in
                Canvas { context,size in draw(context: context,size: size) }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { event in
                        drag(event,size: geometry.size)
                    }.onEnded { _ in
                        if let draft { commit(draft) }
                        draft = nil; dragged = nil
                    })
            }.frame(height: 120).background(Color.primary.opacity(0.04))
            HStack {
                Button("Add Point") {
                    var next = points; let index = min(selected ?? (points.count - 1),points.count - 1)
                    let a = points[index], b = points[(index + 1) % points.count]
                    next.insert(MaskPoint(x: (a.x + b.x) / 2,y: (a.y + b.y) / 2),at: index + 1)
                    selected = index + 1; commit(next)
                }.disabled(points.count >= 64)
                Button("Remove") {
                    guard let selected, points.indices.contains(selected) else { return }
                    var next = points; next.remove(at: selected); self.selected = nil; commit(next)
                }.disabled(selected == nil || points.count <= 3)
            }.controlSize(.mini)
            Text("Drag a vertex to reshape. Add inserts a vertex after the selected point.").font(.system(size: 10)).foregroundStyle(.secondary)
        }.onChange(of: points) { _,_ in if let selected, !points.indices.contains(selected) { self.selected = nil } }
    }
    private func draw(context: GraphicsContext,size: CGSize) {
        let current = draft ?? points
        var path = Path()
        for (index,point) in current.enumerated() {
            let position = CGPoint(x: point.x * size.width,y: (1 - point.y) * size.height)
            if index == 0 { path.move(to: position) } else { path.addLine(to: position) }
        }
        path.closeSubpath()
        context.fill(path,with: .color(Color.accentColor.opacity(0.15)))
        context.stroke(path,with: .color(Color.accentColor),lineWidth: 1)
        for (index,point) in current.enumerated() {
            let x: CGFloat = CGFloat(point.x) * size.width - 3
            let y: CGFloat = (1 - CGFloat(point.y)) * size.height - 3
            let rect = CGRect(x: x,y: y,width: 6,height: 6)
            let color: Color = index == selected ? .accentColor : .primary
            context.fill(Path(ellipseIn: rect),with: .color(color))
        }
    }
    private func drag(_ event: DragGesture.Value,size: CGSize) {
        if dragged == nil {
            var nearest: Int?
            var distance: Double = 18
            for (index,point) in points.enumerated() {
                let dx = point.x * size.width - event.startLocation.x
                let dy = (1 - point.y) * size.height - event.startLocation.y
                let candidate = hypot(dx,dy)
                if candidate <= distance { nearest = index; distance = candidate }
            }
            guard let nearest else { return }
            dragged = nearest; selected = nearest; draft = points
        }
        if let index = dragged {
            let x = max(0,min(1,event.location.x / max(1,size.width)))
            let y = max(0,min(1,1 - event.location.y / max(1,size.height)))
            draft?[index] = MaskPoint(x: x,y: y)
        }
    }

}
