import AppKit
import SwiftUI
import RenderCore

extension EditorSession {
    /// Real native captures for visual review; this does not assert subjective design quality.
    func captureUIReview() async throws {
        guard let path = ProcessInfo.processInfo.environment["RENDER_SCREENSHOT"],let window = NSApp.keyWindow else { return }
        let originalFrame = window.frame
        let originalSelection = selection
        let visibility = (showLibrary,showEffects,showInspector,showTimeline,showAudio)
        defer {
            selection = originalSelection
            showLibrary = visibility.0; showEffects = visibility.1; showInspector = visibility.2
            showTimeline = visibility.3; showAudio = visibility.4
            window.setFrame(originalFrame,display: true); window.makeKeyAndOrderFront(nil)
        }
        func capture(_ target: NSWindow,_ name: String) async throws {
            try await Task.sleep(nanoseconds: 180_000_000)
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-x","-l",String(target.windowNumber),path.replacingOccurrences(of: "workspace-",with: "workspace-\(name)-")]
            try process.run(); process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw RenderError.invalid("Could not capture the \(name) interface.") }
        }
        pause(); closeSource(); seek(30)
        setWorkspace(.editing)
        window.setContentSize(NSSize(width: 960,height: 620))
        try await capture(window,"editing-compact")
        window.setContentSize(NSSize(width: 1280,height: 780))
        try await capture(window,"editing-wide")
        setWorkspace(.audio)
        try await capture(window,"audio")
        let panel = NSWindow(contentRect: NSRect(x: 60,y: 60,width: 530,height: 610),styleMask: [.titled],backing: .buffered,defer: false)
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        panel.contentView = NSHostingView(rootView: ExportView(session: self,exporter: exporter))
        panel.makeKeyAndOrderFront(nil)
        try await capture(panel,"export")
        guard let cameraClip = project.tracks.flatMap(\.clips).first(where: { clip in project.assets.contains { $0.id == clip.assetID && $0.kind == .video } }) else {
            throw RenderError.invalid("Multicam visual review requires the camera fixture.")
        }
        selection = [cameraClip.id]
            panel.contentView = NSHostingView(rootView: MulticamSetupView(session: self))
            panel.setContentSize(NSSize(width: 610,height: 450))
            try await capture(panel,"multicam-setup")
        let empty = EditorSession()
        panel.contentView = NSHostingView(rootView: WorkspaceView(session: empty).frame(minWidth: 960,minHeight: 620))
        panel.setContentSize(NSSize(width: 960,height: 620))
        try await capture(panel,"empty")
        print("RENDER_UI_REVIEW_OK editing-compact editing-wide audio export multicam-setup empty")
    }
}
