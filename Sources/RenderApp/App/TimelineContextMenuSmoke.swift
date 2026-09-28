import AppKit
import SwiftUI
import RenderCore

extension EditorSession {
    func checkTimelineContextMenus(still: MediaAsset) async throws {
        let editor = EditorSession()
        var fixture = RenderProject(); fixture.assets = [still]
        let clip = TimelineClip(assetID: still.id,name: "Menu test",start: 30,duration: 60)
        fixture.tracks[0].clips = [clip]
        editor.commit(fixture,name: "Menu fixture")
        let window = NSWindow(contentRect: NSRect(x: 120,y: 120,width: 960,height: 350),styleMask: [.titled],backing: .buffered,defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close(); editor.pause() }
        let host = NSHostingView(rootView: TimelineView(session: editor)); window.contentView = host
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(nanoseconds: 250_000_000)
        func choose(_ title: String,x: CGFloat,y: CGFloat) async throws {
            var opened = false
            var invoked = false
            var menuTitles: [String] = []
            var contextMenu: NSMenu?
            let itemsObserver = NotificationCenter.default.addObserver(forName: NSMenu.didAddItemNotification,object: nil,queue: .main) { notification in
                if let menu = notification.object as? NSMenu,menu.indexOfItem(withTitle: title) >= 0 { contextMenu = menu }
            }
            let observer = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification,object: nil,queue: .main) { notification in
                guard !opened,let menu = notification.object as? NSMenu else { return }
                opened = true
                let timer = Timer(timeInterval: 0.15,repeats: false) { _ in
                    let target = contextMenu ?? menu
                    menuTitles = target.items.map(\.title)
                    let index = target.indexOfItem(withTitle: title)
                    target.cancelTrackingWithoutAnimation()
                    if index >= 0,target.items[index].isEnabled {
                        target.performActionForItem(at: index); invoked = true
                    }
                }
                RunLoop.main.add(timer,forMode: .eventTracking)
                RunLoop.main.add(timer,forMode: .common)
            }
            defer { NotificationCenter.default.removeObserver(observer); NotificationCenter.default.removeObserver(itemsObserver) }
            let location = host.convert(CGPoint(x: x,y: host.isFlipped ? y : host.bounds.height - y),to: nil)
            for type in [NSEvent.EventType.rightMouseDown,.rightMouseUp] {
                guard let event = NSEvent.mouseEvent(with: type,location: location,modifierFlags: [],timestamp: ProcessInfo.processInfo.systemUptime,windowNumber: window.windowNumber,context: nil,eventNumber: 0,clickCount: 1,pressure: 1) else { throw RenderError.invalid("Cannot create context menu event.") }
                NSApp.postEvent(event,atStart: false)
            }
            let deadline = Date().addingTimeInterval(3)
            while !invoked && Date() < deadline { try await Task.sleep(nanoseconds: 50_000_000) }
            guard invoked else { throw RenderError.invalid("Right-click did not invoke \(title): \(menuTitles).") }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let y = CGFloat(32 + 1 + 28) + TimelineMetrics.laneHeight / 2
        try await choose("Mute Track",x: 110,y: y)
        guard editor.project.tracks[0].muted else { throw RenderError.invalid("Track menu did not mute the clicked track.") }
        editor.undo()
        guard editor.document == fixture else { throw RenderError.invalid("Track context action did not undo.") }
        try await choose("Lock Track",x: 600,y: y)
        guard editor.project.tracks[0].locked else { throw RenderError.invalid("Empty-lane menu did not lock its track.") }
        editor.undo()
        try await choose("Copy",x: 280,y: y)
        guard editor.hasTimelineClipboard,editor.selection == [clip.id] else { throw RenderError.invalid("Clip menu did not target the clicked clip.") }
        editor.openSource(still.id)
        try await choose("Select Clips on Track",x: 110,y: y)
        guard !editor.showingSource,editor.selection == [clip.id] else { throw RenderError.invalid("Track selection menu left keyboard routing in the source viewer.") }
        editor.openSource(still.id)
        let headerPoint = host.convert(CGPoint(x: 40,y: host.isFlipped ? 72 : host.bounds.height - 72),to: nil)
        for type in [NSEvent.EventType.leftMouseDown,.leftMouseUp] {
            guard let event = NSEvent.mouseEvent(with: type,location: headerPoint,modifierFlags: [],timestamp: ProcessInfo.processInfo.systemUptime,windowNumber: window.windowNumber,context: nil,eventNumber: 0,clickCount: 1,pressure: 1) else { throw RenderError.invalid("Cannot create track selection event.") }
            NSApp.postEvent(event,atStart: false)
        }
        try await Task.sleep(nanoseconds: 150_000_000)
        guard !editor.showingSource else { throw RenderError.invalid("Clicking a track header did not restore timeline keyboard routing.") }
        print("RENDER_CONTEXT_MENUS_OK native-right-click header lane clip undo clipboard source-focus")
    }
}
