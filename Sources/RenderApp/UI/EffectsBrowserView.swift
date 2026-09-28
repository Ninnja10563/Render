import SwiftUI
import RenderCore

struct EffectsBrowserView: View {
    @ObservedObject var session: EditorSession
    @State private var search = ""
    @State private var selected: EffectKind? = .exposure
    private let groups: [(String,[EffectKind])] = [
        ("Color",[.exposure,.brightness,.contrast,.saturation,.highlights,.shadows,.temperature,.tint]),
        ("Image",[.gaussianBlur,.sharpen,.vignette]),("Compositing",[.opacity,.chromaKey])
    ]
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("EFFECTS").font(.system(size: 10,weight: .semibold)); Spacer(); Button { session.showEffects = false } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("Hide effects browser") }.foregroundStyle(.secondary).padding(.horizontal,12).frame(height: 32)
            TextField("Search effects",text: $search).textFieldStyle(.roundedBorder).controlSize(.small).padding(.horizontal,10).padding(.bottom,8)
            List(selection: $selected) {
                ForEach(groups,id: \.0) { group in
                    let filtered = group.1.filter { search.isEmpty || $0.label.localizedCaseInsensitiveContains(search) }
                    if !filtered.isEmpty {
                        Section(group.0) {
                            ForEach(filtered,id: \.self) { kind in
                                Text(kind.label).font(.system(size: 11)).tag(kind)
                                    .contextMenu { Button("Apply to Selected Clips") { session.applyEffect(kind) }.disabled(!session.canApplyEffects) }
                                    .onTapGesture(count: 2) { session.applyEffect(kind) }
                            }
                        }
                    }
                }
            }.listStyle(.sidebar)
            Divider()
            VStack(alignment: .leading,spacing: 8) {
                let choice = selected ?? .exposure
                Text(choice.label).font(.system(size: 11,weight: .semibold))
                Text(choice.detail).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false,vertical: true)
                Button("Apply to Selected Clips") { session.applyEffect(choice) }.controlSize(.small).disabled(!session.canApplyEffects)
            }.padding(12).frame(maxWidth: .infinity,alignment: .leading)
        }
    }
}
private extension EffectKind {
    var detail: String {
        switch self {
        case .exposure: return "Adjust exposure in stops."
        case .brightness: return "Offset the image brightness."
        case .contrast: return "Adjust the difference between light and dark."
        case .saturation: return "Control color intensity."
        case .highlights: return "Recover and shape bright image regions."
        case .shadows: return "Lift or deepen dark image regions."
        case .temperature: return "Adjust white balance in kelvin."
        case .tint: return "Shift white balance between green and magenta."
        case .gaussianBlur: return "Soften the image with a Gaussian blur."
        case .sharpen: return "Increase local edge definition."
        case .vignette: return "Darken the edges of the image."
        case .opacity: return "Adjust transparency within the effect stack."
        case .chromaKey: return "Remove a screen color; refine tolerance, edge softness and spill in the inspector."
        }
    }
}
extension EditorSession {
    func isVisualClip(_ clip: TimelineClip) -> Bool {
        if let id = clip.compoundID { return project.compounds?.first(where: { $0.id == id })?.kind == .video }
        return project.assets.first(where: { $0.id == clip.assetID })?.kind != .audio
    }
    func clipHasAudio(_ clip: TimelineClip) -> Bool {
        if let id = clip.compoundID, let source = project.compounds?.first(where: { $0.id == id }) { return source.tracks.flatMap(\.clips).contains { clipHasAudio($0) } }
        guard let media = project.assets.first(where: { $0.id == clip.assetID }) else { return false }
        return media.kind == .audio || media.audioChannels > 0
    }
    var canApplyEffects: Bool {
        !selection.isEmpty && selection.allSatisfy { id in
            guard let location = project.location(id) else { return false }
            return !project.tracks[location.track].locked && isVisualClip(project.tracks[location.track].clips[location.clip])
        }
    }
    func applyEffect(_ kind: EffectKind) {
        guard flushInspectorEdits(), canApplyEffects else { return }
        var next = project
        for t in next.tracks.indices {
            for c in next.tracks[t].clips.indices where selection.contains(next.tracks[t].clips[c].id) { next.tracks[t].clips[c].effects.append(Effect(kind: kind)) }
        }
        commit(next,name: "Add \(kind.label)")
        showInspector = true
    }
}
