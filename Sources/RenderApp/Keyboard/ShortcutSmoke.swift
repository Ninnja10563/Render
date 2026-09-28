import AppKit
import SwiftUI
import RenderCore

extension EditorSession {
    func checkKeyboardShortcuts(delegate: RenderAppDelegate,asset: MediaAsset) async throws {
        guard let window = NSApp.keyWindow,let content = window.contentView else { throw RenderError.invalid("Shortcut check needs an editor window.") }
        let suite = "Render.ShortcutSmoke.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw RenderError.invalid("Cannot isolate shortcut preferences.") }
        let store = ShortcutStore(defaults: defaults),originalStore = delegate.shortcuts,originalTool = tool,originalSnapping = snapping
        defer { delegate.shortcuts = originalStore; tool = originalTool; snapping = originalSnapping; closeSource(); seek(0); defaults.removePersistentDomain(forName: suite) }
        delegate.shortcuts = store
        try store.assign(.init("q"),to: .bladeTool)
        try store.assign(.init("w"),to: .nextFrame)
        guard ShortcutStore(defaults: defaults).map == store.map else { throw RenderError.invalid("Shortcut preferences did not persist.") }
        func post(_ key: String,code: UInt16,flags: NSEvent.ModifierFlags = [],repeatKey: Bool = false,to target: NSWindow? = nil) async throws {
            guard let event = NSEvent.keyEvent(with: .keyDown,location: .zero,modifierFlags: flags,timestamp: ProcessInfo.processInfo.systemUptime,windowNumber: (target ?? window).windowNumber,context: nil,characters: key,charactersIgnoringModifiers: key,isARepeat: repeatKey,keyCode: code) else { throw RenderError.invalid("Cannot generate shortcut event.") }
            NSApp.postEvent(event,atStart: false)
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        window.makeFirstResponder(nil); tool = .select
        try await post("q",code: 12)
        guard tool == .blade else { throw RenderError.invalid("The remapped shortcut did not select Blade.") }
        let menu = NSMenu()
        tool = .select
        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification,object: menu)
        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification,object: menu)
        try await post("q",code: 12)
        guard tool == .select else { throw RenderError.invalid("Editing shortcut intercepted menu input.") }
        NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification,object: menu)
        try await post("q",code: 12)
        guard tool == .select else { throw RenderError.invalid("Closing a submenu resumed editing shortcuts too early.") }
        NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification,object: menu)
        try await post("q",code: 12)
        guard tool == .blade else { throw RenderError.invalid("Editing shortcuts did not resume after menu tracking ended.") }
        tool = .select; try await post("b",code: 11)
        guard tool == .select else { throw RenderError.invalid("The old shortcut still selected Blade.") }
        try store.assign(.init("q",control: true,option: true),to: .trimTool)
        try await post("q",code: 12,flags: [.control,.option])
        guard tool == .trim else { throw RenderError.invalid("Modified shortcut did not select Trim.") }
        tool = .select
        try await post("n",code: 45,repeatKey: true)
        guard snapping == originalSnapping else { throw RenderError.invalid("Held shortcut repeated a toggle.") }
        try store.assign(.init("1",shift: true),to: .selectTool)
        tool = .blade; try await post("!",code: 18,flags: .shift)
        guard tool == .select else { throw RenderError.invalid("Shifted number shortcut did not use its base key.") }
        seek(0); try await post("w",code: 13)
        guard playhead == 1 else { throw RenderError.invalid("Remapped frame movement failed in the timeline.") }
        openSource(asset.id); sourceMonitor.seek(30)
        try await post("w",code: 13)
        guard sourceMonitor.frame == 31,playhead == 1 else { throw RenderError.invalid("Remapped source transport changed the timeline.") }
        try await post("\u{1b}",code: 53)
        guard !showingSource else { throw RenderError.invalid("Escape did not close source context.") }
        let field = NSTextField(frame: NSRect(x: 20,y: 20,width: 180,height: 24))
        content.addSubview(field)
        defer { field.removeFromSuperview() }
        field.selectText(nil)
        guard let text = field.currentEditor() as? NSTextView else { throw RenderError.invalid("Cannot focus shortcut text-entry check.") }
        text.string = ""; tool = .select
        try await post("q",code: 12)
        guard tool == .select,text.string == "q" else { throw RenderError.invalid("Editing shortcut intercepted text input.") }
        window.makeFirstResponder(nil)
        let settings = NSWindow(contentRect: NSRect(x: 120,y: 100,width: 630,height: 570),styleMask: [.titled],backing: .buffered,defer: false)
        settings.isReleasedWhenClosed = false
        defer { settings.close(); window.makeKeyAndOrderFront(nil) }
        settings.contentView = NSHostingView(rootView: ShortcutSettingsView(store: store))
        settings.makeKeyAndOrderFront(nil)
        try await Task.sleep(nanoseconds: 150_000_000)
        settings.makeFirstResponder(nil)
        try await post("q",code: 12,to: settings)
        guard tool == .select else { throw RenderError.invalid("Settings shortcut changed the timeline tool.") }
        if let path = ProcessInfo.processInfo.environment["RENDER_SCREENSHOT"] {
            let capture = Process(); capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x","-l",String(settings.windowNumber),path.replacingOccurrences(of: "workspace-",with: "workspace-shortcuts-")]
            try capture.run(); capture.waitUntilExit()
            guard capture.terminationStatus == 0 else { throw RenderError.invalid("Shortcut settings screenshot failed.") }
        }
        var recorded: NSEvent?
        let recorder = ShortcutCaptureView { recorded = $0 }
        settings.contentView = recorder
        try await Task.sleep(nanoseconds: 50_000_000)
        try await post("q",code: 12,to: settings)
        guard recorded?.characters == "q",tool == .select else { throw RenderError.invalid("Shortcut recorder dispatched an editing action.") }
        try await post("b",code: 11,flags: .command,to: settings)
        guard recorded?.modifierFlags.contains(.command) == true,EditorShortcut(event: recorded!) == nil else { throw RenderError.invalid("The recorder accepted a reserved Command binding.") }
        defaults.set(Data("corrupt shortcuts".utf8),forKey: ShortcutStore.storageKey)
        let recovered = ShortcutStore(defaults: defaults)
        guard recovered.loadError != nil,recovered.map == EditorShortcutMap(),defaults.data(forKey: ShortcutStore.storageKey) == Data("corrupt shortcuts".utf8) else { throw RenderError.invalid("Shortcut recovery discarded the saved data.") }
        print("RENDER_SHORTCUTS_OK native-events persistence context menu-focus text-focus recorder recovery")
    }
}
