import SwiftUI
import AppKit

@main
struct RenderApplication: App {
    @NSApplicationDelegateAdaptor(RenderAppDelegate.self) private var delegate
    @StateObject private var session = EditorSession()
    var body: some Scene {
        Window("Render", id: "editor") {
            WorkspaceView(session: session)
                .frame(minWidth: 960, minHeight: 620)
                .onAppear { delegate.session = session; session.start(); delegate.installKeyboardMonitor() }
                .onOpenURL { session.open($0) }
        }
        .defaultSize(width: 1440, height: 900)
        .commands { EditorCommands(session: session) }
        Settings { SettingsView() }
    }
}

@MainActor
final class RenderAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    weak var session: EditorSession?
    private var monitor: Any?
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--smoke-test") {
            NSApp.appearance = NSAppearance(named: ProcessInfo.processInfo.environment["RENDER_APPEARANCE"] == "dark" ? .darkAqua : .aqua)
        }
        NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            NSApp.windows.first(where: { $0.canBecomeMain })?.delegate = self
            if CommandLine.arguments.contains("--smoke-test") {
                Task { @MainActor in
                    do {
                        guard let session = self?.session else { throw NSError(domain: "RenderSmoke",code: 1) }
                        try await session.runSmokeTest()
                        guard let window = NSApp.windows.first(where: { $0.isVisible }), let view = window.contentView,
                              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(2) }
                        view.cacheDisplay(in: view.bounds, to: bitmap)
                        if let path = ProcessInfo.processInfo.environment["RENDER_SCREENSHOT"] {
                            let capture = Process(); capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                            capture.arguments = ["-x","-l",String(window.windowNumber),path]
                            try capture.run(); capture.waitUntilExit()
                            if capture.terminationStatus != 0 {
                                // AppKit's fallback captures UI but excludes the hardware video layer.
                                guard let png = bitmap.representation(using: .png,properties: [:]) else { exit(2) }
                                try png.write(to: URL(fileURLWithPath: path))
                                print("RENDER_CAPTURE_FALLBACK AppKit snapshot excludes GPU surfaces")
                            }
                        }
                        print("RENDER_SMOKE_OK \(window.frame.width)x\(window.frame.height)")
                        fflush(stdout); NSApp.terminate(nil)
                    } catch { print("RENDER_SMOKE_FAILED \(error.localizedDescription)"); fflush(stdout); exit(3) }
                }
            }
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if CommandLine.arguments.contains("--smoke-test") { return .terminateNow }
        guard let session else { return .terminateNow }
        if session.exporter.isExporting {
            let alert = NSAlert(); alert.messageText = "An export is still running."
            alert.informativeText = "Cancel it before quitting, or wait for it to finish."
            alert.addButton(withTitle: "Keep Exporting"); alert.addButton(withTitle: "Cancel Export and Quit")
            guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
            session.exporter.cancel()
        }
        Task { let proceed = await session.confirmDiscard(); sender.reply(toApplicationShouldTerminate: proceed) }
        return .terminateLater
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { NSApp.terminate(nil); return false }
    func installKeyboardMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let session = self?.session, NSApp.keyWindow?.identifier?.rawValue != "com_apple_SwiftUI_Settings_window",
                  NSApp.modalWindow == nil, NSApp.keyWindow?.attachedSheet == nil,
                  !(NSApp.keyWindow?.firstResponder is NSTextView),
                  event.modifierFlags.intersection([.command,.control,.option]).isEmpty else { return event }
            switch event.keyCode {
            case 49: session.togglePlayback()
            case 123: session.pause(); session.seek(session.playhead - (event.modifierFlags.contains(.shift) ? 10 : 1))
            case 124: session.pause(); session.seek(session.playhead + (event.modifierFlags.contains(.shift) ? 10 : 1))
            case 51,117: session.delete(ripple: event.modifierFlags.contains(.shift))
            case 115: session.seek(0)
            case 119: session.seek(session.project.duration - 1)
            default:
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "j": session.shuttle(-1)
                case "k": session.pause()
                case "l": session.shuttle(1)
                case "a": session.tool = .select
                case "b": session.tool = .blade
                case "t": session.tool = .trim
                case "r": session.tool = .ripple
                case "o": session.tool = .roll
                case "y": session.tool = .slip
                case "u": session.tool = .slide
                case "g": session.tool = .range
                case "z": session.tool = .zoom
                case "n": session.snapping.toggle()
                case "m": session.perform(.marker(.init(frame: session.playhead, name: "Marker \(session.project.markers.count + 1)")))
                default: return event
                }
            }
            return nil
        }
    }
}

private struct SettingsView: View {
    var body: some View {
        Form {
            LabeledContent("Rendering", value: "Core Image / Metal")
            LabeledContent("Project format", value: "Render Project · Version 1")
            LabeledContent("Recovery", value: "After every edit (0.75 second delay)")
            Text("Original media stays in its current location. Use Relink Media if a source moves.").foregroundStyle(.secondary)
        }.padding(24).frame(width: 460)
    }
}
