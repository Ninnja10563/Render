import Foundation
import AVFoundation
import RenderCore

@MainActor
public final class MediaTranscoder {
    private var session: AVAssetExportSession?
    private var cancelled = false
    public private(set) var isRunning = false
    public init() {}
    public func cancel() { cancelled = true; session?.cancelExport() }
    public func generate(_ media: MediaAsset,mode: PlaybackMediaMode,in folder: URL,progress: @escaping (Float) -> Void = { _ in }) async throws -> MediaVariant {
        guard !isRunning, media.kind == .video, mode != .original else { throw RenderError.invalid("Choose video media and a generated-media format.") }
        isRunning = true; cancelled = false
        defer { isRunning = false; session = nil }
        let source = try SourceFingerprint(url: media.url)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
        let id = UUID().uuidString
        let staging = folder.appendingPathComponent(".partial-\(id).mov")
        let destination = folder.appendingPathComponent("\(mode.rawValue)-\(id).mov")
        defer { try? FileManager.default.removeItem(at: staging) }
        let asset = AVURLAsset(url: media.url)
        let preset = mode == .proxy ? AVAssetExportPreset1280x720 : AVAssetExportPresetAppleProRes422LPCM
        guard let exporter = AVAssetExportSession(asset: asset,presetName: preset) else { throw RenderError.invalid("The requested media encoder is unavailable.") }
        session = exporter; exporter.outputURL = staging; exporter.outputFileType = .mov
        exporter.shouldOptimizeForNetworkUse = false
        let monitor = Task { @MainActor in
            while !Task.isCancelled {
                progress(exporter.progress)
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        defer { monitor.cancel() }
        await exporter.export()
        if cancelled || exporter.status == .cancelled { throw CancellationError() }
        guard exporter.status == .completed else { throw exporter.error ?? RenderError.invalid("Media generation failed. Check disk space and source permissions.") }
        guard try SourceFingerprint(url: media.url) == source else { throw RenderError.invalid("Source media changed during generation. Generate it again.") }
        let output = AVURLAsset(url: staging)
        let duration = try await output.load(.duration).seconds
        let videos = try await output.loadTracks(withMediaType: .video)
        guard !videos.isEmpty, duration.isFinite, abs(duration - media.duration) < max(0.1,2 / max(1,media.frameRate)) else {
            throw RenderError.invalid("Generated media does not match the source duration.")
        }
        if cancelled { throw CancellationError() }
        try FileManager.default.moveItem(at: staging,to: destination)
        progress(1)
        return MediaVariant(mode: mode,url: destination,source: source)
    }
}
