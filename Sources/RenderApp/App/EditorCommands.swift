import SwiftUI
import AppKit
import RenderCore

struct EditorCommands: Commands {
    @ObservedObject var session: EditorSession
    private var textEditor: NSTextView? { NSApp.keyWindow?.firstResponder as? NSTextView }
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
            Button("Import Captions (SRT)…") { session.importCaptions() }
            Button("Export Captions (SRT)…") { session.exportCaptions() }
            Button("Export…") { session.showExport = true }.keyboardShortcut("e").disabled(session.project.duration == 0)
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { if let textEditor { textEditor.undoManager?.undo() } else { session.undo() } }.keyboardShortcut("z").disabled(!session.canUndo && textEditor?.undoManager?.canUndo != true)
            Button("Redo") { if let textEditor { textEditor.undoManager?.redo() } else { session.redo() } }.keyboardShortcut("z", modifiers: [.command,.shift]).disabled(!session.canRedo && textEditor?.undoManager?.canRedo != true)
        }
        CommandGroup(replacing: .pasteboard) {
            Button("Cut") { if let textEditor { textEditor.cut(nil) } else { session.cut() } }.keyboardShortcut("x").disabled(session.selection.isEmpty && textEditor == nil)
            Button("Copy") { if let textEditor { textEditor.copy(nil) } else { session.copy() } }.keyboardShortcut("c").disabled(session.selection.isEmpty && textEditor == nil)
            Button("Paste") { if let textEditor { textEditor.paste(nil) } else { session.paste() } }.keyboardShortcut("v")
            Button("Select All") { if let textEditor { textEditor.selectAll(nil) } else { session.selection = Set(session.project.tracks.flatMap(\.clips).map(\.id)) } }.keyboardShortcut("a")
        }
        CommandMenu("Timeline") {
            Button("Split at Playhead") { session.split() }.keyboardShortcut("b")
            Button("Delete") { session.delete() }.disabled(session.selection.isEmpty && session.selectedRange == nil)
            Button("Ripple Delete") { session.delete(ripple: true) }.disabled(session.selection.isEmpty && session.selectedRange == nil)
            Divider()
            Picker("Editing Tool",selection: $session.tool) {
                ForEach(EditingTool.allCases,id: \.self) { Text($0.rawValue).tag($0) }
            }
            Button("Create Multicam Source…") { session.showMulticamSetup = true }.disabled(session.selectedClip?.multicam != nil || session.project.assets.first(where: { $0.id == session.selectedClip?.assetID })?.kind != .video || session.project.assets.filter { $0.kind == .video }.count < 2)
            Toggle("Camera Angle Viewer",isOn: $session.showAngles)
            Button("Synchronize Audio…") { session.showAudioSync = true }.disabled(session.selection.count != 2)
            Button("Detach Audio") { if let clip = session.selectedClip { session.perform(.detachAudio(clip: clip.id)) } }.disabled(session.selectedClip == nil)
            Divider()
            Button("Add Title") { session.addTitle() }.keyboardShortcut("t",modifiers: [.command,.option])
            Button("Add Caption") { session.addTitle(caption: true) }
            Button("Add Video Track") { session.perform(.addTrack(.video)) }
            Button("Add Audio Track") { session.perform(.addTrack(.audio)) }
            Toggle("Magnetic Storyline",isOn: Binding(get: { session.project.storyline?.enabled == true },set: { session.setMagnetic($0) }))
            Button("Connect Selected Clip to Storyline") { session.connectSelectedClip() }.disabled(session.selectedClip == nil || session.primaryStoryline == nil)
            Button("Disconnect Selected Clip") { if let clip = session.selectedClip { session.perform(.connection(clip: clip.id,anchor: nil)) } }.disabled(session.selectedClip?.connection == nil)
            Button("Insert Two-Second Gap") { session.insertGap() }
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
