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
    public var audioChannels: Int
    public init(url: URL, kind: MediaKind, duration: Double, width: Int = 0, height: Int = 0, frameRate: Double = 0, codec: String = "", audioChannels: Int = 0) {
        self.url = url; name = url.lastPathComponent; self.kind = kind; self.duration = duration
        self.width = width; self.height = height; self.frameRate = frameRate; self.codec = codec; self.audioChannels = audioChannels
    }
}
public enum TrackKind: String, Codable, Sendable { case video, audio }
public struct TimelineClip: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var assetID: UUID
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
    public init(assetID: UUID, name: String, start: Int64, duration: Int64) {
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
    public static let currentSchema = 1
    public var schemaVersion = currentSchema
    public var id = UUID()
    public var name = "Untitled"
    public var settings = ProjectSettings()
    public var assets: [MediaAsset] = []
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
        guard settings.width >= 16, settings.width <= 8192, settings.height >= 16, settings.height <= 8192,
              settings.width % 2 == 0, settings.height % 2 == 0,
              settings.frameRate.numerator > 0, settings.frameRate.denominator > 0,
              (1...120).contains(settings.frameRate.value) else { throw RenderError.invalid("Invalid project dimensions or frame rate.") }
        let ids = assets.map(\.id) + tracks.map(\.id) + tracks.flatMap(\.clips).map(\.id) + markers.map(\.id)
        guard Set(ids).count == ids.count else { throw RenderError.invalid("Project contains duplicate identifiers.") }
        for asset in assets {
            guard asset.url.isFileURL, asset.duration.isFinite, asset.duration > 0,
                  asset.frameRate.isFinite, asset.audioChannels >= 0 else { throw RenderError.invalid("Invalid media metadata for \(asset.name).") }
        }
        for track in tracks {
            var previousEnd: Int64 = 0
            for clip in track.clips.sorted(by: { $0.start < $1.start }) {
                guard clip.start >= 0, clip.duration > 0, clip.start < 100_000_000,
                      clip.duration < 100_000_000, clip.animationOffset >= 0,
                      clip.sourceIn.isFinite, clip.sourceIn >= 0, clip.speed.isFinite, (0.05...16).contains(clip.speed)
                else { throw RenderError.invalid("Invalid timing for \(clip.name).") }
                guard clip.start >= previousEnd else { throw RenderError.invalid("Clips cannot overlap on the same track. Move the clip to another track.") }
                previousEnd = clip.end
                guard let asset = assets.first(where: { $0.id == clip.assetID }) else { throw RenderError.invalid("Clip references an unknown media asset.") }
                guard (track.kind == .audio) == (asset.kind == .audio) else { throw RenderError.invalid("This media belongs on a \(asset.kind == .audio ? "audio" : "video") track.") }
                if asset.kind != .image {
                    guard clip.sourceIn + settings.frameRate.seconds(clip.duration) * clip.speed <= asset.duration + 0.001 else { throw RenderError.invalid("Edit extends past the available source media.") }
                }
                let p = clip.properties
                guard [p.x,p.y,p.scale,p.rotation,p.opacity,p.volume].allSatisfy(\.isFinite),
                      (0.01...10).contains(p.scale), (0...1).contains(p.opacity), (0...4).contains(p.volume),
                      abs(p.x) <= 32768, abs(p.y) <= 32768, abs(p.rotation) <= 3600 else { throw RenderError.invalid("Invalid clip properties.") }
                for (name, curve) in p.animations {
                    guard ["x","y","scale","rotation","opacity","volume"].contains(name) else { throw RenderError.invalid("Unknown animated property.") }
                    try Self.validateCurve(curve)
                    let range: ClosedRange<Double>
                    switch name { case "scale": range = 0.01...10; case "opacity": range = 0...1; case "volume": range = 0...4; case "rotation": range = -3600...3600; default: range = -32768...32768 }
                    guard curve.keys.allSatisfy({ range.contains($0.value) }) else { throw RenderError.invalid("Keyframe value is outside the property range.") }
                }
                guard Set(clip.effects.map(\.id)).count == clip.effects.count else { throw RenderError.invalid("Duplicate effects.") }
                for effect in clip.effects {
                    guard effect.amount.isFinite, effect.kind.range.contains(effect.amount) else { throw RenderError.invalid("Effect value is out of range.") }
                    try Self.validateCurve(effect.animation)
                    guard effect.animation.keys.allSatisfy({ effect.kind.range.contains($0.value) }) else { throw RenderError.invalid("Effect keyframe is out of range.") }
                }
            }
        }
        guard markers.allSatisfy({ $0.frame >= 0 && $0.frame < 100_000_000 }) else { throw RenderError.invalid("Invalid marker position.") }
    }
    private static func validateCurve(_ curve: AnimationCurve) throws {
        guard Set(curve.keys.map(\.frame)).count == curve.keys.count,
              Set(curve.keys.map(\.id)).count == curve.keys.count,
              curve.keys.allSatisfy({ $0.frame >= 0 && $0.frame < 200_000_000 && $0.value.isFinite }) else { throw RenderError.invalid("Invalid keyframe curve.") }
    }
}
