import AppKit
import UniformTypeIdentifiers
import RenderCore

extension EditorSession {
    func addTitle(caption: Bool = false) {
        let title = TitleContent(text: caption ? "Caption" : "Title",role: caption ? .caption : .title)
        perform(.addTitle(title,at: playhead,duration: fps.frames(5)))
        if let clip = project.tracks.first?.clips.first { selection = [clip.id]; selectedAsset = nil }
    }
    func importCaptions() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "srt") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let document = project.id, rate = fps
        activity = "Reading captions…"
        Task {
            defer { if project.id == document { activity = nil } }
            do {
                let cues = try await Task.detached(priority: .userInitiated) {
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= 8 * 1024 * 1024 else { throw RenderError.invalid("Caption file exceeds 8 MB.") }
                    return try SRTCodec.decode(String(contentsOf: url,encoding: .utf8),rate: rate)
                }.value
                guard project.id == document, fps == rate else { return }
                guard !cues.isEmpty else { throw RenderError.invalid("No captions found in this SRT file.") }
                perform(.captions(cues))
            } catch { if project.id == document { report(error) } }
        }
    }
    func exportCaptions() {
        let cues = project.tracks.filter { !$0.hidden }.flatMap(\.clips).compactMap { clip -> CaptionCue? in
            guard let title = clip.title, title.role == .caption else { return nil }
            return CaptionCue(start: clip.start,end: clip.end,text: title.text)
        }
        guard !cues.isEmpty else { errorMessage = "There are no captions on visible tracks to export."; return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [UTType(filenameExtension: "srt") ?? .plainText]
        panel.nameFieldStringValue = project.name + ".srt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let rate = fps
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    let text = try SRTCodec.encode(cues,rate: rate)
                    try Data(text.utf8).write(to: url,options: .atomic)
                }.value
            } catch { report(error) }
        }
    }
}
