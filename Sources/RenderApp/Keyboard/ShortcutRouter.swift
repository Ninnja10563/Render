import AppKit
import RenderCore

@MainActor
enum ShortcutRouter {
    static func handle(_ event: NSEvent,session: EditorSession,store: ShortcutStore) -> Bool {
        // Escape is always available to cancel editing; it cannot be rebound.
        if event.keyCode == 53,event.modifierFlags.intersection([.command,.control,.option,.shift]).isEmpty {
            if session.showingSource { session.closeSource() } else { session.timelineDrag.cancel() }
            return true
        }
        let context: ShortcutContext = session.showingSource ? .source : .timeline
        guard let shortcut = EditorShortcut(event: event),let action = store.map.action(for: shortcut,in: context) else { return false }
        if event.isARepeat && !action.allowsRepeat { return true }
        if session.showingSource {
            let source = session.sourceMonitor
            switch action {
            case .playPause: source.togglePlayback()
            case .reverse: source.shuttle(-1)
            case .stop: source.pause()
            case .forward: source.shuttle(1)
            case .previousFrame: source.seek(source.frame - 1)
            case .nextFrame: source.seek(source.frame + 1)
            case .previousTenFrames: source.seek(source.frame - 10)
            case .nextTenFrames: source.seek(source.frame + 10)
            case .beginning: source.seek(0)
            case .end: source.seek(source.totalFrames - 1)
            case .markIn: session.markSource(incoming: true)
            case .markOut: session.markSource(incoming: false)
            default: return false
            }
        } else {
            switch action {
            case .playPause: session.togglePlayback()
            case .reverse: session.shuttle(-1)
            case .stop: session.pause()
            case .forward: session.shuttle(1)
            case .previousFrame: session.pause(); session.seek(session.playhead - 1)
            case .nextFrame: session.pause(); session.seek(session.playhead + 1)
            case .previousTenFrames: session.pause(); session.seek(session.playhead - 10)
            case .nextTenFrames: session.pause(); session.seek(session.playhead + 10)
            case .beginning: session.seek(0)
            case .end: session.seek(session.project.duration - 1)
            case .selectTool: session.tool = .select
            case .bladeTool: session.tool = .blade
            case .trimTool: session.tool = .trim
            case .rippleTool: session.tool = .ripple
            case .rollTool: session.tool = .roll
            case .slipTool: session.tool = .slip
            case .slideTool: session.tool = .slide
            case .rangeTool: session.tool = .range
            case .zoomTool: session.tool = .zoom
            case .delete: session.delete()
            case .rippleDelete: session.delete(ripple: true)
            case .snapping: session.snapping.toggle()
            case .marker: session.perform(.marker(.init(frame: session.playhead,name: "Marker \(session.project.markers.count + 1)")))
            default: return false
            }
        }
        return true
    }
}
