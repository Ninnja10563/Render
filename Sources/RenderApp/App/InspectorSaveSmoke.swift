import AppKit
import SwiftUI
import RenderCore

extension EditorSession {
    /// Exercises a real native field editor without Return or a focus change before Save.
    func checkFocusedInspectorSave(clipID: UUID,folder: URL) async throws {
        let window = NSWindow(contentRect: NSRect(x: 100,y: 100,width: 320,height: 120),styleMask: [.titled],backing: .buffered,defer: false)
        window.isReleasedWhenClosed = false
        let originalURL = documentURL, originalName = project.name
        defer { window.close(); documentURL = originalURL; project.name = originalName }
        window.contentView = NSHostingView(rootView: InspectorNumber(label: "Save Validation",value: 0,range: -1000...1000,reset: 0) { [weak self] value in
            self?.setProperty("x",value: value,clipID: clipID)
        }.padding())
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(nanoseconds: 100_000_000)
        func editable(_ view: NSView) -> NSTextField? {
            if let field = view as? NSTextField, field.isEditable { return field }
            return view.subviews.lazy.compactMap { editable($0) }.first
        }
        guard let field = window.contentView.flatMap(editable) else { throw RenderError.invalid("Inspector save test could not find its native text field.") }
        field.selectText(nil)
        guard let editor = field.currentEditor() as? NSTextView else { throw RenderError.invalid("Inspector save test could not focus its field.") }
        editor.string = "125"; editor.didChangeText()
        try await Task.sleep(nanoseconds: 50_000_000)
        let url = folder.appendingPathComponent("Focused Draft.renderproject")
        documentURL = url
        guard await save() else { throw RenderError.invalid("Saving a focused inspector draft failed.") }
        let stored = try await ProjectStore().load(url)
        guard stored.clip(clipID)?.properties.x == 125 else { throw RenderError.invalid("Save omitted the focused numeric edit.") }
        editor.string = "not-a-number"; editor.didChangeText()
        try await Task.sleep(nanoseconds: 50_000_000)
        let rejected = await save()
        errorMessage = nil
        guard !rejected else { throw RenderError.invalid("Save accepted an invalid inspector draft.") }
        editor.string = "125"; editor.didChangeText()
        try await Task.sleep(nanoseconds: 50_000_000)
        window.makeFirstResponder(nil)
        undo()
        guard project.clip(clipID)?.properties.x == 0 else { throw RenderError.invalid("Focused inspector edit did not retain undo.") }
        print("RENDER_INSPECTOR_SAVE_OK focused-field persisted invalid-draft rejected undo")
    }
}
