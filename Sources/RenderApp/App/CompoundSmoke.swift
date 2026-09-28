import AppKit
import RenderCore

extension EditorSession {
    func checkCompoundEditing(folder: URL,still: MediaAsset) async throws {
        let editor = EditorSession()
        var fixture = RenderProject(); fixture.name = "Compound Document"; fixture.assets = [still]
        let original = TimelineClip(assetID: still.id,name: "Nested source",start: 0,duration: 90)
        fixture.tracks[0].clips = [original]
        editor.commit(fixture,name: "Fixture"); editor.selection = [original.id]; editor.createCompound(name: "Scene")
        guard let parent = editor.selectedClip, let sourceID = parent.compoundID else { throw RenderError.invalid("Compound creation did not select its parent.") }
        editor.copy()
        editor.openCompound(sourceID)
        guard editor.compoundPath == [sourceID], editor.project.clip(original.id) != nil else { throw RenderError.invalid("Compound source did not open.") }
        editor.selection = [original.id]; editor.selectedTrack = editor.project.tracks[0].id
        editor.setProperty("x",value: 42)
        guard editor.document.clip(parent.id) != nil, editor.document.compounds?.first?.tracks[0].clips.first?.properties.x == 42 else { throw RenderError.invalid("Nested edits were not merged into the root document.") }
        let beforePaste = editor.document
        editor.paste()
        guard editor.errorMessage != nil, editor.document == beforePaste else { throw RenderError.invalid("Pasting a compound into itself was not rejected atomically.") }
        editor.errorMessage = nil
        let url = folder.appendingPathComponent("Compound Saved From Inside.renderproject")
        editor.documentURL = url
        guard await editor.save() else { throw RenderError.invalid("Could not save from inside a compound.") }
        let stored = try await ProjectStore().load(url)
        guard stored.clip(parent.id) != nil, stored.compounds?.first?.tracks[0].clips.first?.properties.x == 42 else { throw RenderError.invalid("Saving inside a compound lost the outer timeline.") }
        editor.returnToTimeline(depth: 0)
        editor.undo()
        guard editor.project.compounds?.first?.tracks[0].clips.first?.properties.x == 0, editor.isDirty else { throw RenderError.invalid("Undo after navigation restored the wrong timeline.") }
        editor.redo()
        guard editor.project.compounds?.first?.tracks[0].clips.first?.properties.x == 42, !editor.isDirty else { throw RenderError.invalid("Redo after navigation did not restore saved document state.") }
        editor.perform(.breakApart(parent.id))
        guard editor.project.tracks.flatMap(\.clips).contains(where: { $0.assetID == still.id && $0.properties.x == 42 }), editor.project.clip(parent.id) == nil else { throw RenderError.invalid("Break apart lost child edits.") }
        editor.undo(); editor.openCompound(sourceID); editor.undo()
        guard editor.compoundPath == [sourceID], editor.project.clip(original.id)?.properties.x == 0 else { throw RenderError.invalid("Root undo did not refresh the active compound context.") }
        editor.undo()
        guard editor.compoundPath.isEmpty, editor.project.clip(original.id) != nil else { throw RenderError.invalid("Undoing compound creation left a stale navigation context.") }
        editor.redo(); editor.openCompound(sourceID)
        let deadline = Date().addingTimeInterval(10)
        while !editor.previewReady {
            if let error = editor.previewError { throw RenderError.invalid(error) }
            guard Date() < deadline else { throw RenderError.invalid("Nested timeline playback did not become ready.") }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        print("RENDER_COMPOUND_OK create open edit root-save cycle-rejection navigation-undo break-apart playback")
    }
}
