import Foundation
import AVFoundation
import RenderCore

@MainActor
public final class ExportService: ObservableObject {
    @Published public private(set) var progress: Float = 0
    @Published public private(set) var isExporting = false
    @Published public private(set) var elapsed: TimeInterval = 0
    private var session: AVAssetExportSession?
    private var cancelled = false
    public init() {}
    public func cancel() { cancelled = true; session?.cancelExport() }
    public func export(project: RenderProject, configuration: ExportConfiguration, to destination: URL) async throws {
        guard !isExporting else { throw RenderError.invalid("An export is already running.") }
        try configuration.validate()
        guard !project.assets.contains(where: { $0.url.standardizedFileURL == destination.standardizedFileURL }) else { throw RenderError.invalid("Export cannot overwrite source media.") }
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw RenderError.invalid("Choose a new output filename; Render does not overwrite existing files.") }
        isExporting = true; cancelled = false; progress = 0; elapsed = 0
        let start = Date()
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".render-export-\(UUID().uuidString).\(configuration.codec == .proRes ? "mov" : "mp4")")
        defer { isExporting = false; session = nil; try? FileManager.default.removeItem(at: temporary) }
        var snapshot = project
        // Keep timeline units unchanged; only the compositor's output cadence changes.
        snapshot.settings.width = configuration.width; snapshot.settings.height = configuration.height
        let prepared = try await CompositionBuilder().build(snapshot)
        if cancelled { throw CancellationError() }
        prepared.videoComposition.frameDuration = CMTime(value: Int64(configuration.frameRate.denominator), timescale: configuration.frameRate.numerator)
        let preset: String
        switch configuration.codec {
        case .h264: preset = AVAssetExportPresetHighestQuality
        case .hevc: preset = AVAssetExportPresetHEVCHighestQuality
        case .proRes: preset = AVAssetExportPresetAppleProRes422LPCM
        }
        guard let exporter = AVAssetExportSession(asset: prepared.composition, presetName: preset) else { throw RenderError.invalid("This export codec is unavailable on this Mac.") }
        session = exporter
        exporter.outputURL = temporary
        exporter.outputFileType = configuration.codec == .proRes ? .mov : .mp4
        exporter.videoComposition = prepared.videoComposition; exporter.audioMix = prepared.audioMix
        // Bound the output explicitly; time-pitch processing can otherwise expose an audio tail.
        exporter.timeRange = CMTimeRange(start: .zero,duration: CMTime(value: project.duration * Int64(project.settings.frameRate.denominator),timescale: project.settings.frameRate.numerator))
        exporter.shouldOptimizeForNetworkUse = true
        let monitor = Task { @MainActor in
            while !Task.isCancelled {
                progress = exporter.progress; elapsed = Date().timeIntervalSince(start)
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        defer { monitor.cancel() }
        await exporter.export()
        if cancelled || exporter.status == .cancelled { throw CancellationError() }
        guard exporter.status == .completed else { throw exporter.error ?? RenderError.invalid("Export failed. Check available disk space and media permissions.") }
        // A completed file is published only after the encoder finishes successfully.
        try FileManager.default.moveItem(at: temporary, to: destination)
        progress = 1; elapsed = Date().timeIntervalSince(start)
    }
}
