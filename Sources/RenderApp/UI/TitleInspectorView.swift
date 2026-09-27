import SwiftUI
import AppKit
import RenderCore

struct TitleInspectorView: View {
    @ObservedObject var session: EditorSession
    let clip: TimelineClip
    let title: TitleContent
    var body: some View {
        VStack(alignment: .leading,spacing: 10) {
            Text(title.role == .caption ? "Caption" : "Title").font(.system(size: 11,weight: .semibold))
            TextEditor(text: Binding(get: { title.text },set: { value in change { $0.text = value } })).font(.system(size: 12)).frame(height: 80)
                .overlay(Rectangle().stroke(Color.secondary.opacity(0.2),lineWidth: 1))
            Picker("Font",selection: Binding(get: { title.fontFamily },set: { value in change { $0.fontFamily = value } })) {
                if !FontFamilies.names.contains(title.fontFamily) { Text("\(title.fontFamily) (unavailable)").tag(title.fontFamily) }
                ForEach(FontFamilies.names,id: \.self) { name in Text(name).tag(name) }
            }
            Picker("Weight",selection: Binding(get: { title.weight },set: { value in change { $0.weight = value } })) {
                Text("Light").tag(-0.4); Text("Regular").tag(0.0); Text("Medium").tag(0.23); Text("Bold").tag(0.4); Text("Heavy").tag(0.56)
            }
            InspectorNumber(label: "Font Size",value: title.fontSize,range: 8...500,reset: 72) { value in change { $0.fontSize = value } }
            Picker("Alignment",selection: Binding(get: { title.alignment },set: { value in change { $0.alignment = value } })) {
                Text("Left").tag(RenderCore.TextAlignment.left)
                Text("Center").tag(RenderCore.TextAlignment.center)
                Text("Right").tag(RenderCore.TextAlignment.right)
            }
            ColorPicker("Text Colour",selection: color(\.color),supportsOpacity: true)
            ColorPicker("Outline",selection: color(\.outline),supportsOpacity: true)
            InspectorNumber(label: "Outline Width",value: title.outlineWidth,range: 0...30,reset: 0) { value in change { $0.outlineWidth = value } }
            DisclosureGroup("Shadow & Background") {
                ColorPicker("Shadow",selection: color(\.shadow),supportsOpacity: true)
                InspectorNumber(label: "Blur",value: title.shadowBlur,range: 0...100,reset: 4) { value in change { $0.shadowBlur = value } }
                InspectorNumber(label: "Shadow X",value: title.shadowX,range: -500...500,reset: 0) { value in change { $0.shadowX = value } }
                InspectorNumber(label: "Shadow Y",value: title.shadowY,range: -500...500,reset: -2) { value in change { $0.shadowY = value } }
                ColorPicker("Background",selection: color(\.background),supportsOpacity: true)
                InspectorNumber(label: "Padding",value: title.padding,range: 0...200,reset: 16) { value in change { $0.padding = value } }
            }
            InspectorNumber(label: "Start (seconds)",value: session.fps.seconds(clip.start),range: 0...max(600,session.fps.seconds(session.project.duration)),reset: 0) { value in
                session.perform(.move(clips: [clip.id],delta: session.fps.frames(value) - clip.start))
            }
            InspectorNumber(label: "Duration (seconds)",value: session.fps.seconds(clip.duration),range: session.fps.seconds(1)...600,reset: 5) { value in
                session.perform(.trim(clip: clip.id,edge: .trailing,to: clip.start + max(1,session.fps.frames(value))))
            }
            Divider()
        }.font(.system(size: 10))
    }
    private func change(_ edit: (inout TitleContent) -> Void) { var next = title; edit(&next); session.perform(.title(clip: clip.id,next)) }
    private func color(_ path: WritableKeyPath<TitleContent,RGBAColor>) -> Binding<Color> {
        Binding(get: {
            let value = title[keyPath: path]
            return Color(.sRGB,red: value.red,green: value.green,blue: value.blue,opacity: value.alpha)
        },set: { value in
            guard let rgb = NSColor(value).usingColorSpace(.sRGB) else { return }
            change { $0[keyPath: path] = RGBAColor(rgb.redComponent,rgb.greenComponent,rgb.blueComponent,rgb.alphaComponent) }
        })
    }
}

@MainActor
private enum FontFamilies { static let names = NSFontManager.shared.availableFontFamilies.sorted() }
