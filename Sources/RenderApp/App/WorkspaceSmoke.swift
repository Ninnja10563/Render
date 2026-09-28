import AppKit
import AVFoundation
import RenderCore

extension EditorSession {
    func checkWorkspaceControls() async throws {
        guard let clip = selectedClip else { throw RenderError.invalid("Workspace check needs a selected clip.") }
        let original = document
        setWorkspace(.effects)
        guard showEffects, !showLibrary, showInspector, showTimeline else { throw RenderError.invalid("Effects workspace did not open.") }
        applyEffect(.gaussianBlur)
        guard project.clip(clip.id)?.effects.last?.kind == .gaussianBlur else { throw RenderError.invalid("Effects browser did not apply the chosen effect.") }
        undo()
        guard document == original else { throw RenderError.invalid("Effect browser bypassed root undo.") }
        redo(); undo()
        setWorkspace(.audio)
        guard showAudio, !showEffects, !showInspector, showTimeline else { throw RenderError.invalid("Audio workspace did not open.") }
        setWorkspace(.viewer)
        guard !showTimeline, !showAudio, !showEffects, !showInspector, !showLibrary else { throw RenderError.invalid("Viewer workspace did not hide editing panels.") }
        setWorkspace(.effects); showAudio = true
        previewQuality = .half
        let deadline = Date().addingTimeInterval(10)
        while !previewReady {
            if let error = previewError { throw RenderError.invalid(error) }
            guard Date() < deadline else { throw RenderError.invalid("Reduced-resolution preview did not become ready.") }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let dims = previewQuality.dimensions(for: project.settings)
        guard player.currentItem?.videoComposition?.renderSize == CGSize(width: dims.width,height: dims.height), document == original else { throw RenderError.invalid("Preview quality changed document state or failed to resize the render target.") }
        print("RENDER_WORKSPACE_OK effects apply undo audio viewer half-resolution document-unchanged")
    }
}
