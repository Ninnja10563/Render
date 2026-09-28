import AppKit
import SwiftUI
import RenderCore

struct ShortcutSettingsView: View {
    @ObservedObject var store: ShortcutStore
    @State private var search = ""
    @State private var recording: EditorShortcutAction?
    @State private var error: String?
    @State private var confirmingReset = false
    var body: some View {
        VStack(alignment: .leading,spacing: 12) {
            Text("Editing Shortcuts").font(.headline)
            Text("Bindings apply to the timeline, source viewer, or both. Standard macOS menu commands and Escape keep their usual functions.")
                .font(.callout).foregroundStyle(.secondary)
            TextField("Search commands",text: $search).textFieldStyle(.roundedBorder)
            if let message = error ?? store.loadError { Text(message).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false,vertical: true) }
            ScrollView {
                LazyVStack(spacing: 0,pinnedViews: [.sectionHeaders]) {
                    ForEach(["Transport","Timeline","Source"],id: \.self) { category in
                        let actions = EditorShortcutAction.allCases.filter { $0.category == category && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || store.label($0).localizedCaseInsensitiveContains(search)) }
                        if !actions.isEmpty {
                            Section {
                                ForEach(actions) { action in
                                    HStack(spacing: 10) {
                                        Text(action.title)
                                        Spacer()
                                        Button(store.label(action)) { error = nil; recording = action }
                                            .frame(width: 115).help("Change \(action.title)")
                                            .accessibilityLabel("\(action.title), \(store.label(action)). Change shortcut")
                                        Button { change { try store.assign(nil,to: action) } } label: { Image(systemName: "xmark") }
                                            .buttonStyle(.borderless).frame(width: 22).disabled(store.map.shortcut(for: action) == nil).help("Clear \(action.title)")
                                            .accessibilityLabel("Clear \(action.title)")
                                        Button { change { try store.assign(action.defaultShortcut,to: action) } } label: { Image(systemName: "arrow.counterclockwise") }
                                            .buttonStyle(.borderless).frame(width: 22).disabled(store.map.shortcut(for: action) == action.defaultShortcut).help("Restore \(action.title) default")
                                            .accessibilityLabel("Restore \(action.title) default")
                                    }.padding(.vertical,6)
                                    Divider()
                                }
                            } header: {
                                HStack { Text(category.uppercased()).font(.system(size: 10,weight: .semibold)).foregroundStyle(.secondary); Spacer(); Text(category == "Transport" ? "Timeline and Source" : category).font(.caption).foregroundStyle(.secondary) }
                                    .padding(.vertical,8).background(Color(nsColor: .windowBackgroundColor))
                            }
                        }
                    }
                }
            }
            HStack {
                Text("Changes are saved automatically on this Mac.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Restore All Defaults…") { confirmingReset = true }
            }
        }.padding(20).frame(width: 590,height: 530)
            .sheet(item: $recording) { action in ShortcutRecordingSheet(action: action,store: store) }
            .alert("Restore all editing shortcuts?",isPresented: $confirmingReset) {
                Button("Cancel",role: .cancel) {}
                Button("Restore Defaults") { change { try store.reset() } }
            } message: { Text("Your custom bindings will be replaced with Render's defaults.") }
    }
    private func change(_ operation: () throws -> Void) {
        do { try operation(); error = nil } catch { self.error = error.localizedDescription }
    }
}

private struct ShortcutRecordingSheet: View {
    let action: EditorShortcutAction
    @ObservedObject var store: ShortcutStore
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading,spacing: 14) {
            Text(action.title).font(.headline)
            Text("Press a letter, number, arrow, Space, Home, End or Delete. You can include Shift, Control or Option.").foregroundStyle(.secondary)
            ShortcutCapture(receive: { event in
                if event.keyCode == 53 { dismiss(); return }
                guard let shortcut = EditorShortcut(event: event) else {
                    error = "This key is reserved or unsupported. Command shortcuts belong to the native menus."; return
                }
                do { try store.assign(shortcut,to: action); dismiss() }
                catch { self.error = error.localizedDescription }
            }).frame(height: 42).overlay { Text("Press shortcut · Esc to cancel").foregroundStyle(.secondary).allowsHitTesting(false) }
                .background(Color(nsColor: .textBackgroundColor))
            if let error { Text(error).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false,vertical: true) }
            HStack { Spacer(); Button("Cancel") { dismiss() } }
        }.padding(24).frame(width: 430)
    }
}

struct ShortcutCapture: NSViewRepresentable {
    let receive: (NSEvent) -> Void
    func makeNSView(context: Context) -> ShortcutCaptureView { ShortcutCaptureView(receive: receive) }
    func updateNSView(_ view: ShortcutCaptureView,context: Context) { view.receive = receive }
}

final class ShortcutCaptureView: NSView {
    var receive: (NSEvent) -> Void
    init(receive: @escaping (NSEvent) -> Void) {
        self.receive = receive; super.init(frame: .zero)
        setAccessibilityElement(true); setAccessibilityRole(.textField); setAccessibilityLabel("Record editing shortcut")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in guard let self else { return }; self.window?.makeFirstResponder(self) }
    }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
    override func keyDown(with event: NSEvent) { if !event.isARepeat { receive(event) } }
}
