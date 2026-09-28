import SwiftUI
import RenderCore

struct AudioEffectsInspectorView: View {
    @ObservedObject var session: EditorSession
    let clip: TimelineClip
    private var effects: [AudioEffect] { clip.properties.audioEffects ?? [] }
    private var supported: Bool {
        guard clip.compoundID == nil,let id = clip.assetID,let asset = session.project.assets.first(where: { $0.id == id }) else { return false }
        return (1...8).contains(asset.audioChannels)
    }
    var body: some View {
        VStack(alignment: .leading,spacing: 10) {
            Text("Audio Effects").font(.system(size: 11,weight: .semibold))
            if supported {
                ForEach(Array(effects.enumerated()),id: \.element.id) { index,effect in
                    VStack(alignment: .leading,spacing: 8) {
                        HStack(spacing: 6) {
                            Toggle(effect.kind.label,isOn: Binding(get: { effect.enabled },set: { value in edit(index) { $0.enabled = value } })).font(.system(size: 11))
                            Spacer(minLength: 0)
                            Button { edit(index) { $0.values = [:] } } label: { Image(systemName: "arrow.counterclockwise") }.help("Reset audio effect")
                            Button { var stack = effects; stack.swapAt(index,index - 1); save(stack) } label: { Image(systemName: "arrow.up") }.disabled(index == 0).help("Move audio effect earlier")
                            Button { var stack = effects; stack.remove(at: index); save(stack) } label: { Image(systemName: "xmark") }.help("Remove audio effect")
                        }.buttonStyle(.plain)
                        DisclosureGroup("Parameters") {
                            VStack(spacing: 8) {
                                ForEach(effect.kind.parameters,id: \.key) { parameter in
                                    InspectorNumber(label: parameter.label,value: effect.value(parameter.key),range: parameter.range,reset: parameter.defaultValue) { value in edit(index) { $0.values[parameter.key] = value } }
                                }
                            }.padding(.top,6)
                        }.font(.system(size: 10)).disabled(!effect.enabled)
                    }
                }
                Menu { ForEach(AudioEffectKind.allCases,id: \.self) { kind in Button(kind.label) { save(effects + [AudioEffect(kind: kind)]) } } } label: { Label("Add Audio Effect",systemImage: "plus") }.disabled(effects.count >= 16)
                Text("Effects run in order before clip volume and fades. The limiter controls sample peaks before the fader.").font(.system(size: 10)).foregroundStyle(.secondary)
            } else if clip.compoundID != nil {
                Text("Open the compound timeline to process its source clips.").font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                Text("Audio effects support sources with up to eight channels.").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Divider()
        }
    }
    private func edit(_ index: Int,change: (inout AudioEffect) -> Void) {
        var stack = effects; change(&stack[index]); save(stack)
    }
    private func save(_ stack: [AudioEffect]) {
        var properties = clip.properties; properties.audioEffects = stack.isEmpty ? nil : stack
        session.perform(.properties(clip: clip.id,properties))
    }
}
