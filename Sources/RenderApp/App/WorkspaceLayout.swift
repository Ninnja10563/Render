import Foundation

enum WorkspaceLayout { case editing, effects, audio, viewer }
extension EditorSession {
    func setWorkspace(_ layout: WorkspaceLayout) {
        guard flushInspectorEdits() else { return }
        showLibrary = layout == .editing
        showEffects = layout == .effects
        showAudio = layout == .audio
        showInspector = layout == .editing || layout == .effects
        showTimeline = layout != .viewer
        if layout == .viewer { showAngles = false }
    }
}
