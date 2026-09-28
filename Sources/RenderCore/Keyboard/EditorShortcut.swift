import Foundation

public enum ShortcutContext: String, Codable, CaseIterable, Sendable { case timeline, source }

/// Logical keys, independent of a keyboard's physical scan codes. Command combinations
/// remain owned by the native application menus and text system.
public struct EditorShortcut: Codable, Equatable, Hashable, Sendable {
    public var key: String
    public var shift: Bool
    public var control: Bool
    public var option: Bool
    public init(_ key: String,shift: Bool = false,control: Bool = false,option: Bool = false) {
        self.key = key.lowercased(); self.shift = shift; self.control = control; self.option = option
    }
    public var isValid: Bool {
        ["space","left","right","home","end","delete"].contains(key) ||
        (key.utf8.count == 1 && key.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) })
    }
    public var label: String {
        let name = ["space":"Space","left":"←","right":"→","home":"Home","end":"End","delete":"Delete"][key] ?? key.uppercased()
        return (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + name
    }
}

public enum EditorShortcutAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case playPause, reverse, stop, forward, previousFrame, nextFrame, previousTenFrames, nextTenFrames, beginning, end
    case selectTool, bladeTool, trimTool, rippleTool, rollTool, slipTool, slideTool, rangeTool, zoomTool
    case delete, rippleDelete, snapping, marker, markIn, markOut
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .playPause: return "Play / Pause"
        case .reverse: return "Shuttle Reverse"
        case .stop: return "Stop"
        case .forward: return "Shuttle Forward"
        case .previousFrame: return "Previous Frame"
        case .nextFrame: return "Next Frame"
        case .previousTenFrames: return "Back Ten Frames"
        case .nextTenFrames: return "Forward Ten Frames"
        case .beginning: return "Go to Beginning"
        case .end: return "Go to End"
        case .selectTool: return "Selection Tool"
        case .bladeTool: return "Blade Tool"
        case .trimTool: return "Trim Tool"
        case .rippleTool: return "Ripple Tool"
        case .rollTool: return "Roll Tool"
        case .slipTool: return "Slip Tool"
        case .slideTool: return "Slide Tool"
        case .rangeTool: return "Range Tool"
        case .zoomTool: return "Zoom Tool"
        case .delete: return "Delete"
        case .rippleDelete: return "Ripple Delete"
        case .snapping: return "Toggle Snapping"
        case .marker: return "Add Marker"
        case .markIn: return "Mark In"
        case .markOut: return "Mark Out"
        }
    }
    public var contexts: Set<ShortcutContext> {
        switch self {
        case .playPause,.reverse,.stop,.forward,.previousFrame,.nextFrame,.previousTenFrames,.nextTenFrames,.beginning,.end: return [.timeline,.source]
        case .markIn,.markOut: return [.source]
        default: return [.timeline]
        }
    }
    public var category: String {
        contexts.count == 2 ? "Transport" : contexts.contains(.source) ? "Source" : "Timeline"
    }
    public var defaultShortcut: EditorShortcut {
        switch self {
        case .playPause: return .init("space")
        case .reverse: return .init("j")
        case .stop: return .init("k")
        case .forward: return .init("l")
        case .previousFrame: return .init("left")
        case .nextFrame: return .init("right")
        case .previousTenFrames: return .init("left",shift: true)
        case .nextTenFrames: return .init("right",shift: true)
        case .beginning: return .init("home")
        case .end: return .init("end")
        case .selectTool: return .init("a")
        case .bladeTool: return .init("b")
        case .trimTool: return .init("t")
        case .rippleTool: return .init("r")
        case .rollTool: return .init("o")
        case .slipTool: return .init("y")
        case .slideTool: return .init("u")
        case .rangeTool: return .init("g")
        case .zoomTool: return .init("z")
        case .delete: return .init("delete")
        case .rippleDelete: return .init("delete",shift: true)
        case .snapping: return .init("n")
        case .marker: return .init("m")
        case .markIn: return .init("i")
        case .markOut: return .init("o")
        }
    }
    /// Frame navigation can repeat while held; document mutations and toggles cannot.
    public var allowsRepeat: Bool {
        [.previousFrame,.nextFrame,.previousTenFrames,.nextTenFrames].contains(self)
    }
}

public struct EditorShortcutMap: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public private(set) var version = currentVersion
    private var overrides: [String: EditorShortcut] = [:]
    private var disabled: Set<String> = []
    public init() {}
    public func shortcut(for action: EditorShortcutAction) -> EditorShortcut? {
        disabled.contains(action.rawValue) ? nil : overrides[action.rawValue] ?? action.defaultShortcut
    }
    public func action(for shortcut: EditorShortcut,in context: ShortcutContext) -> EditorShortcutAction? {
        EditorShortcutAction.allCases.first { $0.contexts.contains(context) && self.shortcut(for: $0) == shortcut }
    }
    public func conflict(for shortcut: EditorShortcut,assigning action: EditorShortcutAction) -> EditorShortcutAction? {
        EditorShortcutAction.allCases.first { $0 != action && !$0.contexts.isDisjoint(with: action.contexts) && self.shortcut(for: $0) == shortcut }
    }
    public mutating func assign(_ shortcut: EditorShortcut?,to action: EditorShortcutAction) throws {
        if let shortcut {
            guard shortcut.isValid else { throw RenderError.invalid("Choose A–Z, 0–9, a left/right arrow, Space, Home, End or Delete, optionally with Shift, Control or Option.") }
            if let other = conflict(for: shortcut,assigning: action) {
                throw RenderError.invalid("\(shortcut.label) is already assigned to \(other.title). Clear or change that binding first.")
            }
            disabled.remove(action.rawValue)
            if shortcut == action.defaultShortcut { overrides.removeValue(forKey: action.rawValue) }
            else { overrides[action.rawValue] = shortcut }
        } else {
            overrides.removeValue(forKey: action.rawValue); disabled.insert(action.rawValue)
        }
    }
    public func validate() throws {
        guard version == Self.currentVersion else { throw RenderError.invalid("This shortcut file uses an unsupported version.") }
        let known = Set(EditorShortcutAction.allCases.map(\.rawValue))
        guard Set(overrides.keys).isSubset(of: known),disabled.isSubset(of: known),Set(overrides.keys).isDisjoint(with: disabled) else {
            throw RenderError.invalid("The saved shortcut bindings are invalid.")
        }
        for action in EditorShortcutAction.allCases {
            if let shortcut = shortcut(for: action) {
                guard shortcut.isValid,conflict(for: shortcut,assigning: action) == nil else { throw RenderError.invalid("The saved shortcuts contain invalid or conflicting bindings.") }
            }
        }
    }
}
