import Foundation

public enum MediaKind: String, Codable, Sendable { case video, audio, image }
public struct MediaAsset: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var url: URL
    public var name: String
    public var kind: MediaKind
    public var duration: Double
    public var width: Int
    public var height: Int
    public var frameRate: Double
    public var codec: String
    public var variants: [MediaVariant]?
    public var audioChannels: Int
    public init(url: URL, kind: MediaKind, duration: Double, width: Int = 0, height: Int = 0, frameRate: Double = 0, codec: String = "", audioChannels: Int = 0) {
        self.url = url; name = url.lastPathComponent; self.kind = kind; self.duration = duration
        self.width = width; self.height = height; self.frameRate = frameRate; self.codec = codec; self.audioChannels = audioChannels
    }
}
public enum TrackKind: String, Codable, Sendable { case video, audio }
public struct TimelineClip: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var assetID: UUID?
    public var title: TitleContent?
    public var isGap: Bool?
    public var connection: ClipConnection?
    public var transition: ClipTransition?
    public var multicam: MulticamMembership?
    public var compoundID: UUID?
    public var name: String
    public var start: Int64
    public var duration: Int64
    public var sourceIn: Double = 0
    public var speed: Double = 1
    /// Retains animation phase through splits and trims.
    public var animationOffset: Int64 = 0
    public var properties = ClipProperties()
    public var effects: [Effect] = []
    public var end: Int64 { start + duration }
    public init(assetID: UUID?, name: String, start: Int64, duration: Int64) {
        self.assetID = assetID; self.name = name; self.start = start; self.duration = duration
    }
}
public struct TimelineTrack: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var kind: TrackKind
    public var locked = false
    public var hidden = false
    public var muted = false
    public var solo = false
    public var clips: [TimelineClip] = []
    public init(name: String, kind: TrackKind) { self.name = name; self.kind = kind }
}
public struct TimelineMarker: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var frame: Int64
    public var name: String
    public init(frame: Int64, name: String) { self.frame = frame; self.name = name }
}
public struct ProjectSettings: Codable, Equatable, Sendable {
    public var width = 1920
    public var height = 1080
    public var frameRate = FrameRate()
    public init() {}
}
public struct RenderProject: Codable, Equatable, Identifiable, Sendable {
    public static let currentSchema = 11
    public var schemaVersion = currentSchema
    public var id = UUID()
    public var name = "Untitled"
    public var settings = ProjectSettings()
    public var assets: [MediaAsset] = []
    public var storyline: StorylineSettings?
    public var multicamSources: [MulticamSource]?
    public var compounds: [CompoundSource]?
    /// Topmost video track composites above subsequent video tracks.
    public var tracks = [TimelineTrack(name: "Video 1", kind: .video), TimelineTrack(name: "Audio 1", kind: .audio)]
    public var markers: [TimelineMarker] = []
    public init() {}
    public var duration: Int64 { tracks.flatMap(\.clips).map(\.end).max() ?? 0 }
    public func clip(_ id: UUID) -> TimelineClip? { tracks.flatMap(\.clips).first { $0.id == id } }
    public func location(_ id: UUID) -> (track: Int, clip: Int)? {
        for (t, track) in tracks.enumerated() {
            if let c = track.clips.firstIndex(where: { $0.id == id }) { return (t, c) }
        }
        return nil
    }
    public func validate() throws {
        guard schemaVersion == Self.currentSchema else { throw RenderError.unsupportedVersion(schemaVersion) }
        try settings.validate()
        let ids = assets.map(\.id) + tracks.map(\.id) + tracks.flatMap(\.clips).map(\.id) + markers.map(\.id)
        let cameraIDs = (multicamSources ?? []).flatMap { [$0.id] + $0.angles.map(\.id) }
        let compoundIDs = (compounds ?? []).flatMap { [$0.id] + $0.tracks.map(\.id) + $0.tracks.flatMap(\.clips).map(\.id) + $0.markers.map(\.id) }
        guard Set(ids + cameraIDs + compoundIDs).count == ids.count + cameraIDs.count + compoundIDs.count else { throw RenderError.invalid("Project contains duplicate identifiers.") }
        for asset in assets {
            let variants = asset.variants ?? []
            guard (variants.isEmpty || asset.kind == .video), variants.count <= 2, Set(variants.map(\.mode)).count == variants.count,
                  variants.allSatisfy({ $0.mode != .original && $0.url.isFileURL && $0.source.url.isFileURL && $0.source.size >= 0 && $0.source.modified.timeIntervalSince1970.isFinite }) else {
                throw RenderError.invalid("Invalid proxy or optimized media reference.")
            }
            guard asset.url.isFileURL, asset.duration.isFinite, asset.duration > 0, asset.duration <= 604800,
                  asset.frameRate.isFinite, asset.audioChannels >= 0 else { throw RenderError.invalid("Invalid media metadata for \(asset.name).") }
        }
        let mediaByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id,$0) })
        for source in multicamSources ?? [] { try source.validate(assets: mediaByID) }
        let multicams = Dictionary(uniqueKeysWithValues: (multicamSources ?? []).map { ($0.id,$0) })
        let sources = Dictionary(uniqueKeysWithValues: (compounds ?? []).map { ($0.id,$0) })
        for source in sources.values {
            try source.settings.validate()
            guard !source.name.isEmpty, source.name.utf8.count <= 4096, source.duration > 0, source.duration < 100_000_000,
                  source.kind != .audio || source.tracks.allSatisfy({ $0.kind == .audio }) else { throw RenderError.invalid("Invalid compound source settings.") }
        }
        try validateTimeline(mediaByID: mediaByID,multicams: multicams,sources: sources)
        for source in sources.values {
            var context = self
            context.settings = source.settings; context.tracks = source.tracks; context.markers = source.markers; context.storyline = source.storyline
            try context.validateTimeline(mediaByID: mediaByID,multicams: multicams,sources: sources)
            guard context.duration <= source.duration else { throw RenderError.invalid("Compound contents extend beyond its declared source duration.") }
        }
        try validateCompoundGraph(sources)
    }
}
