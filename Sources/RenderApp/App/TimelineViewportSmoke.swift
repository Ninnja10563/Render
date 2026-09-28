import AppKit
import SwiftUI
import RenderCore

@MainActor
enum TimelineRenderProbe {
    static var horizontal: [UUID: CGFloat] = [:]
    static func horizontalOffset(_ value: CGFloat,project: UUID) { if CommandLine.arguments.contains("--smoke-test") { horizontal[project] = value } }
    static var visible: Set<UUID> = []
    static func appear(_ id: UUID) { if CommandLine.arguments.contains("--smoke-test") { visible.insert(id) } }
    static func disappear(_ id: UUID) { if CommandLine.arguments.contains("--smoke-test") { visible.remove(id) } }
}

extension EditorSession {
    func checkTimelineViewport() async throws {
        let test = EditorSession()
        test.project.tracks = (0..<500).map { TimelineTrack(name: "Track \($0)",kind: .video) }
        let ids = Set(test.project.tracks.map(\.id))
        let window = NSWindow(contentRect: NSRect(x: 100,y: 100,width: 960,height: 350),styleMask: [.titled],backing: .buffered,defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close(); TimelineRenderProbe.visible.subtract(ids); TimelineRenderProbe.horizontal[test.project.id] = nil }
        window.contentView = NSHostingView(rootView: TimelineView(session: test))
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(nanoseconds: 200_000_000)
        func verticalScroll(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView, scroll.hasVerticalScroller { return scroll }
            return view.subviews.lazy.compactMap { verticalScroll($0) }.first
        }
        guard let scroll = window.contentView.flatMap(verticalScroll) else { throw RenderError.invalid("Timeline test could not find the vertical scroll view.") }
        let initial = TimelineRenderProbe.visible.intersection(ids)
        guard initial.contains(test.project.tracks[0].id), initial.count <= 12 else { throw RenderError.invalid("Offscreen timeline tracks were constructed at the top of the viewport.") }
        let desiredY: CGFloat = 28 + 250 * TimelineMetrics.laneHeight
        let nativeY = scroll.documentView?.isFlipped == false ? max(0,(scroll.documentView?.bounds.height ?? 0) - scroll.contentView.bounds.height - desiredY) : desiredY
        scroll.contentView.scroll(to: NSPoint(x: 0,y: nativeY))
        scroll.reflectScrolledClipView(scroll.contentView)
        try await Task.sleep(nanoseconds: 200_000_000)
        let middle = TimelineRenderProbe.visible.intersection(ids)
        guard middle.contains(test.project.tracks[250].id), !middle.contains(test.project.tracks[0].id), middle.count <= 12 else { throw RenderError.invalid("Timeline viewport mismatch: rows \(test.project.tracks.indices.filter { middle.contains(test.project.tracks[$0].id) }), bounds \(scroll.contentView.bounds), document \(scroll.documentView?.bounds ?? .zero), flipped \(scroll.documentView?.isFlipped ?? false).") }
        func horizontalScroll(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView, scroll.hasHorizontalScroller { return scroll }
            return view.subviews.lazy.compactMap { horizontalScroll($0) }.first
        }
        guard let horizontal = window.contentView.flatMap(horizontalScroll) else { throw RenderError.invalid("Horizontal timeline scroll view missing.") }
        horizontal.contentView.scroll(to: NSPoint(x: 150,y: horizontal.contentView.bounds.minY))
        horizontal.reflectScrolledClipView(horizontal.contentView)
        try await Task.sleep(nanoseconds: 200_000_000)
        guard abs((TimelineRenderProbe.horizontal[test.project.id] ?? -1) - 150) < 1 else { throw RenderError.invalid("Horizontal timeline viewport did not follow native scrolling.") }
        print("RENDER_VIEWPORT_OK 500-tracks \(middle.count)-visible-lanes native-scroll")
    }
}
