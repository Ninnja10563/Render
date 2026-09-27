import SwiftUI
import RenderCore

struct EditorCommands: Commands {
    @ObservedObject var session: EditorSession
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Project") { session.newProject() }.keyboardShortcut("n")
            Button("Open Project…") { session.openPanel() }.keyboardShortcut("o")
            Menu("Open Recent") {
                ForEach(session.recentURLs, id: \.self) { url in Button(url.deletingPathExtension().lastPathComponent) { session.open(url) } }
                if session.recentURLs.isEmpty { Text("No Recent Projects") }
            }
            Button("Duplicate Project") { session.duplicate() }
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") { Task { _ = await session.save() } }.keyboardShortcut("s")
            Button("Save As…") { Task { _ = await session.save(asNew: true) } }.keyboardShortcut("s", modifiers: [.command,.shift])
            Divider()
            Button("Import Media…") { session.importPanel() }.keyboardShortcut("i").disabled(session.importing)
            Button("Export…") { session.showExport = true }.keyboardShortcut("e").disabled(session.project.duration == 0)
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { session.undo() }.keyboardShortcut("z").disabled(!session.canUndo)
            Button("Redo") { session.redo() }.keyboardShortcut("z", modifiers: [.command,.shift]).disabled(!session.canRedo)
        }
        CommandGroup(replacing: .pasteboard) {
            Button("Cut") { session.cut() }.keyboardShortcut("x").disabled(session.selection.isEmpty)
            Button("Copy") { session.copy() }.keyboardShortcut("c").disabled(session.selection.isEmpty)
            Button("Paste") { session.paste() }.keyboardShortcut("v")
            Button("Select All Clips") { session.selection = Set(session.project.tracks.flatMap(\.clips).map(\.id)) }.keyboardShortcut("a")
        }
        CommandMenu("Timeline") {
            Button("Split at Playhead") { session.split() }.keyboardShortcut("b")
            Button("Delete") { session.delete() }.disabled(session.selection.isEmpty && session.selectedRange == nil)
            Button("Ripple Delete") { session.delete(ripple: true) }.disabled(session.selection.isEmpty && session.selectedRange == nil)
            Divider()
            Picker("Editing Tool",selection: $session.tool) {
                ForEach(EditingTool.allCases,id: \.self) { Text($0.rawValue).tag($0) }
            }
            Button("Detach Audio") { if let clip = session.selectedClip { session.perform(.detachAudio(clip: clip.id)) } }.disabled(session.selectedClip == nil)
            Divider()
            Button("Add Video Track") { session.perform(.addTrack(.video)) }
            Button("Add Audio Track") { session.perform(.addTrack(.audio)) }
            Toggle("Snapping", isOn: $session.snapping)
            Button("Add Marker") { session.perform(.marker(.init(frame: session.playhead,name: "Marker"))) }
        }
        CommandGroup(after: .sidebar) {
            Toggle("Media Browser", isOn: $session.showLibrary).keyboardShortcut("1",modifiers: [.command,.option])
            Toggle("Inspector", isOn: $session.showInspector).keyboardShortcut("2",modifiers: [.command,.option])
            Toggle("Timeline", isOn: $session.showTimeline).keyboardShortcut("3",modifiers: [.command,.option])
        }
    }
}
