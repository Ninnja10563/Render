import AppKit
import SwiftUI
import RenderCore

extension EditorSession {
    func checkTrackDragging(still: MediaAsset) async throws {
        let editor = EditorSession(); editor.snapping = false
        var fixture = RenderProject(); fixture.assets = [still]
        fixture.tracks = [TimelineTrack(name: "Upper",kind: .video),TimelineTrack(name: "Lower",kind: .video)]
        let clip = TimelineClip(assetID: still.id,name: "Drag test",start: 30,duration: 60)
        fixture.tracks[0].clips = [clip]; editor.commit(fixture,name: "Drag fixture"); editor.selectClip(clip.id)
        let window = NSWindow(contentRect: NSRect(x: 120,y: 120,width: 960,height: 350),styleMask: [.titled],backing: .buffered,defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close(); editor.pause() }
        let host = NSHostingView(rootView: TimelineView(session: editor)); window.contentView = host
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(nanoseconds: 250_000_000)
        func point(_ x: CGFloat,_ top: CGFloat) -> CGPoint { host.convert(CGPoint(x: x,y: host.isFlipped ? top : host.bounds.height - top),to: nil) }
        func post(_ type: NSEvent.EventType,_ x: CGFloat,_ top: CGFloat) throws {
            guard let event = NSEvent.mouseEvent(with: type,location: point(x,top),modifierFlags: [],timestamp: ProcessInfo.processInfo.systemUptime,windowNumber: window.windowNumber,context: nil,eventNumber: 0,clickCount: 1,pressure: type == .leftMouseUp ? 0 : 1) else { throw RenderError.invalid("Cannot create native drag event.") }
            NSApp.postEvent(event,atStart: false)
        }
        try post(.leftMouseDown,280,105)
        try await Task.sleep(nanoseconds: 40_000_000)
        for step in 1...10 {
            try post(.leftMouseDragged,280 + CGFloat(step) * 7,105 + CGFloat(step) * 7)
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard editor.timelineDrag.active,editor.timelineDrag.trackOffset == 1 else { throw RenderError.invalid("Native mouse drag did not preview the destination lane.") }
        try post(.leftMouseUp,350,175)
        try await Task.sleep(nanoseconds: 150_000_000)
        guard editor.project.tracks[0].clips.isEmpty,editor.project.tracks[1].clips.first?.id == clip.id,
              editor.project.clip(clip.id)?.start == 60,!editor.timelineDrag.active else { throw RenderError.invalid("Native track drag did not commit the intended time and lane: \(editor.errorMessage ?? "no error").") }
        editor.undo()
        guard editor.document == fixture else { throw RenderError.invalid("Track drag did not undo as a single transaction.") }
        editor.redo(); editor.undo()
        try editor.timelineDrag.begin(project: editor.project,selection: [clip.id])
        editor.timelineDrag.update(delta: 30,trackOffset: 1); editor.timelineDrag.cancel()
        guard try editor.timelineDrag.finish() == nil,editor.document == fixture else { throw RenderError.invalid("Cancelling a drag changed the project.") }
        print("RENDER_TRACK_DRAG_OK native-mouse time lane undo redo cancel")
    }
}
