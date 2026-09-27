import Foundation

public enum PlaybackMediaMode: String, Codable, CaseIterable, Sendable {
    case original, proxy, optimized
    public var label: String { rawValue.capitalized }
}
public struct SourceFingerprint: Codable, Equatable, Sendable {
    public var url: URL
    public var size: Int64
    public var modified: Date
    public init(url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber, let modified = attributes[.modificationDate] as? Date else {
            throw RenderError.invalid("Cannot read source media identity.")
        }
        self.url = url.standardizedFileURL; self.size = size.int64Value; self.modified = modified
    }
}
public struct MediaVariant: Codable, Equatable, Sendable {
    public var mode: PlaybackMediaMode
    public var url: URL
    public var source: SourceFingerprint
    public init(mode: PlaybackMediaMode,url: URL,source: SourceFingerprint) { self.mode = mode; self.url = url; self.source = source }
}
public enum MediaResolver {
    /// A missing/stale cache falls back to the original. Available proxies also support offline editing.
    public static func url(for media: MediaAsset,mode: PlaybackMediaMode) -> URL {
        guard mode != .original, media.kind == .video,
              let variant = media.variants?.first(where: { $0.mode == mode }),
              variant.source.url == media.url.standardizedFileURL,
              FileManager.default.fileExists(atPath: variant.url.path) else { return media.url }
        if FileManager.default.fileExists(atPath: media.url.path) {
            guard let current = try? SourceFingerprint(url: media.url), current == variant.source else { return media.url }
        }
        return variant.url
    }
}
