import AppKit
import SwiftUI
import RenderCore

extension EditorSession {
    func checkSourceMonitor(folder: URL) async throws {
        let asset = try await library.analyze(folder.appendingPathComponent("Meter playback.wav"))
        let editor = EditorSession()
        var fixture = RenderProject(); fixture.settings.width = 320; fixture.settings.height = 180; fixture.assets = [asset]
        fixture.tracks[1].clips = [TimelineClip(assetID: asset.id,name: "Existing edit",start: 0,duration: 30)]
        editor.commit(fixture,name: "Source fixture")
        let deadline = Date().addingTimeInterval(8)
        while !editor.previewReady { guard Date() < deadline else { throw RenderError.invalid("Source test timeline did not prepare.") }; try await Task.sleep(nanoseconds: 30_000_000) }
        let timelineItem = editor.player.currentItem
        editor.openSource(asset.id)
        editor.waveforms[asset.id] = try await library.waveform(asset,bins: 300)
        let window = NSWindow(contentRect: NSRect(x: 140,y: 140,width: 600,height: 380),styleMask: [.titled],backing: .buffered,defer: false)
        window.isReleasedWhenClosed = false; window.contentView = NSHostingView(rootView: SourceViewer(session: editor)); window.makeKeyAndOrderFront(nil)
        defer { editor.sourceMonitor.pause(); editor.pause(); window.close() }
        while !editor.sourceMonitor.ready {
            if let error = editor.sourceMonitor.error { throw RenderError.invalid(error) }
            guard Date() < deadline else { throw RenderError.invalid("Source media did not become ready.") }
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        editor.sourceMonitor.seek(30); editor.markSource(incoming: true)
        editor.sourceMonitor.seek(59); editor.markSource(incoming: false)
        guard editor.sourceMonitor.range == SourceSelection(start: 1,end: 2),editor.player.currentItem === timelineItem,editor.project.tracks == fixture.tracks else { throw RenderError.invalid("Source marks rebuilt or changed the existing timeline.") }
        if let path = ProcessInfo.processInfo.environment["RENDER_SCREENSHOT"] {
            try await Task.sleep(nanoseconds: 100_000_000)
            let screenshot = URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("workspace-source-\(ProcessInfo.processInfo.environment["RENDER_APPEARANCE"] ?? "dark").png")
            let capture = Process(); capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x","-l",String(window.windowNumber),screenshot.path]
            try capture.run(); capture.waitUntilExit()
            guard capture.terminationStatus == 0 else { throw RenderError.invalid("Cannot capture the installed source viewer.") }
        }
        let saved = folder.appendingPathComponent("Source Marks.renderproject")
        try await ProjectStore().save(editor.document,to: saved)
        let reopened = try await ProjectStore().load(saved)
        guard reopened.assets[0].selection == SourceSelection(start: 1,end: 2) else { throw RenderError.invalid("Source marks were not saved.") }
        editor.sourceMonitor.seek(30); editor.sourceMonitor.togglePlayback()
        let playingDeadline = Date().addingTimeInterval(3)
        while editor.sourceMonitor.frame <= 30 && Date() < playingDeadline { try await Task.sleep(nanoseconds: 30_000_000) }
        guard editor.sourceMonitor.frame > 30,editor.playhead == 0 else { throw RenderError.invalid("Source transport did not stay independent of the timeline playhead.") }
        editor.sourceMonitor.pause(); editor.editSource()
        guard editor.project.tracks[1].clips.count == 2,editor.project.tracks[1].clips.last?.sourceIn == 1,editor.project.tracks[1].clips.last?.duration == 30 else { throw RenderError.invalid("Append did not use the source marks.") }
        editor.undo()
        guard editor.project.tracks == fixture.tracks else { throw RenderError.invalid("Source range insertion did not undo atomically.") }
        editor.clearSourceMarks(); guard editor.sourceMonitor.asset?.selection == nil else { throw RenderError.invalid("Clear marks failed.") }
        editor.undo(); guard editor.sourceMonitor.range == SourceSelection(start: 1,end: 2) else { throw RenderError.invalid("Source mark undo failed.") }
        editor.selectClip(fixture.tracks[1].clips[0].id); guard !editor.showingSource,!editor.sourceMonitor.playing else { throw RenderError.invalid("Returning to the timeline left source playback active.") }
        editor.openSource(asset.id)
        while editor.canUndo && editor.project.assets.contains(where: { $0.id == asset.id }) { editor.undo() }
        guard !editor.showingSource,editor.sourceMonitor.asset == nil else { throw RenderError.invalid("Undoing source import left an orphaned player.") }
        var recovered = asset; recovered.url = folder.appendingPathComponent("Recovered Source.wav")
        editor.sourceMonitor.configure(recovered,rate: editor.fps)
        guard editor.sourceMonitor.error != nil else { throw RenderError.invalid("Missing source media was not reported.") }
        try FileManager.default.copyItem(at: asset.url,to: recovered.url)
        editor.sourceMonitor.configure(recovered,rate: editor.fps)
        let recoveredDeadline = Date().addingTimeInterval(3)
        while !editor.sourceMonitor.ready && Date() < recoveredDeadline { try await Task.sleep(nanoseconds: 30_000_000) }
        guard editor.sourceMonitor.ready,editor.sourceMonitor.error == nil else { throw RenderError.invalid("Recovered source media could not be reopened.") }
        editor.sourceMonitor.clear()
        var nested = try CompoundEditing.create([fixture.tracks[1].clips[0].id],name: "Different rate",in: fixture)
        nested.compounds![0].settings.frameRate = FrameRate(24)
        let sourceID = nested.compounds![0].id
        editor.commit(nested,name: "Source navigation fixture")
        editor.openCompound(sourceID); editor.openSource(asset.id)
        editor.sourceMonitor.seek(24); editor.markSource(incoming: true)
        guard editor.sourceMonitor.rate == FrameRate(24),editor.sourceMonitor.range.start == 1 else { throw RenderError.invalid("Source marks used the wrong timeline time base.") }
        editor.returnToTimeline(depth: 0)
        try await Task.sleep(nanoseconds: 30_000_000)
        guard !editor.showingSource,!editor.sourceMonitor.playing,editor.fps == FrameRate(),editor.document.assets[0].selection?.start == 1 else { throw RenderError.invalid("Returning to the parent retained a stale source transport.") }
        editor.openSource(asset.id); editor.openCompound(sourceID)
        try await Task.sleep(nanoseconds: 30_000_000)
        guard !editor.showingSource,editor.fps == FrameRate(24) else { throw RenderError.invalid("Opening a compound retained source-viewer focus.") }
        print("RENDER_SOURCE_NAVIGATION_OK compound parent differing-frame-rates")
        print("RENDER_SOURCE_OK native-view playback marks append undo save independent-transport")
    }
}
