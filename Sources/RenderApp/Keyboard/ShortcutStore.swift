import SwiftUI
import RenderCore

@MainActor
final class ShortcutStore: ObservableObject {
    static let shared = ShortcutStore()
    static let storageKey = "Render.EditorShortcuts.v1"
    @Published private(set) var map = EditorShortcutMap()
    @Published var loadError: String?
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: Self.storageKey) else { return }
        do {
            let saved = try JSONDecoder().decode(EditorShortcutMap.self,from: data)
            try saved.validate(); map = saved
        } catch {
            loadError = "Saved shortcuts could not be loaded. Defaults are active; the saved data is retained until you change or reset a binding. \(error.localizedDescription)"
        }
    }
    func assign(_ shortcut: EditorShortcut?,to action: EditorShortcutAction) throws {
        var next = map; try next.assign(shortcut,to: action); try save(next)
    }
    func reset() throws { try save(EditorShortcutMap()) }
    private func save(_ next: EditorShortcutMap) throws {
        try next.validate()
        let data = try JSONEncoder().encode(next)
        defaults.set(data,forKey: Self.storageKey); map = next; loadError = nil
    }
    func label(_ action: EditorShortcutAction) -> String { map.shortcut(for: action)?.label ?? "Unassigned" }
}

extension EditorShortcut {
    init?(event: NSEvent) {
        guard event.modifierFlags.intersection([.command]).isEmpty else { return nil }
        let named: [UInt16:String] = [49:"space",123:"left",124:"right",115:"home",119:"end",51:"delete",117:"delete"]
        // Strip Shift as well as Option/Control before comparing the logical base key.
        // charactersIgnoringModifiers alone retains Shift (e.g. Shift-1 becomes "!").
        let characters = event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers
        guard let key = named[event.keyCode] ?? characters?.lowercased() else { return nil }
        self.init(key,shift: event.modifierFlags.contains(.shift),control: event.modifierFlags.contains(.control),option: event.modifierFlags.contains(.option))
        guard isValid else { return nil }
    }
}
