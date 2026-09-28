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
    public static let currentSchema = 9
    public var schemaVersion = currentSchema
    public var id = UUID()
    public var name = "Untitled"
    public var settings = ProjectSettings()
    public var assets: [MediaAsset] = []
    public var storyline: StorylineSettings?
    public var multicamSources: [MulticamSource]?
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
        let cameraIDs = (multicamSources ?? []).flatMap { [$0.id] + $0.angles.map(\.id) }
        guard Set(ids + cameraIDs).count == ids.count + cameraIDs.count else { throw RenderError.invalid("Project contains duplicate identifiers.") }
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
        for track in tracks {
            let trackClips = track.clips.contains(where: { $0.transition != nil }) ? Dictionary(uniqueKeysWithValues: track.clips.map { ($0.id,$0) }) : [:]
            var previousEnd: Int64 = 0
            for clip in track.clips.sorted(by: { $0.start < $1.start }) {
                guard clip.start >= 0, clip.duration > 0, clip.start < 100_000_000,
                      clip.duration < 100_000_000, clip.animationOffset >= 0, clip.animationOffset < 100_000_000,
                      clip.sourceIn.isFinite, clip.sourceIn >= 0, clip.speed.isFinite, (0.05...16).contains(clip.speed)
                else { throw RenderError.invalid("Invalid timing for \(clip.name).") }
                guard clip.start >= previousEnd else { throw RenderError.invalid("Clips cannot overlap on the same track. Move the clip to another track.") }
                previousEnd = clip.end
                if let transition = clip.transition {
                    guard track.kind == .video else { throw RenderError.invalid("Visual transitions belong on video tracks.") }
                    try TransitionEditing.validate(transition,left: clip,right: trackClips[transition.rightID],project: self,assets: mediaByID)
                }
                if clip.isGap == true {
                    guard clip.assetID == nil, clip.title == nil, track.kind == .video else { throw RenderError.invalid("A gap must be a generated video clip.") }
                } else if let title = clip.title {
                    guard clip.assetID == nil, track.kind == .video else { throw RenderError.invalid("Titles must be generated clips on video tracks.") }
                    try title.validate()
                } else {
                    guard let assetID = clip.assetID, let asset = mediaByID[assetID] else { throw RenderError.invalid("Clip references an unknown media asset.") }
                    guard (track.kind == .audio) == (asset.kind == .audio) else { throw RenderError.invalid("This media belongs on a \(asset.kind == .audio ? "audio" : "video") track.") }
                    if asset.kind != .image {
                        guard clip.sourceIn + settings.frameRate.seconds(clip.duration) * clip.speed <= asset.duration + 0.001 else { throw RenderError.invalid("Edit extends past the available source media.") }
                    }
                }
                if let membership = clip.multicam {
                    guard track.kind == .video, clip.title == nil, clip.isGap != true,
                          let source = multicams[membership.sourceID], let angle = source.angles.first(where: { $0.id == membership.angleID }),
                          clip.assetID == angle.assetID else { throw RenderError.invalid("Invalid multicam clip reference.") }
                }
                let p = clip.properties
                try p.geometry?.validate()
                try p.audioFades?.validate()
                guard [p.x,p.y,p.scale,p.rotation,p.opacity,p.volume].allSatisfy(\.isFinite),
                      (0.01...10).contains(p.scale), (0...1).contains(p.opacity), (0...4).contains(p.volume),
                      abs(p.x) <= 32768, abs(p.y) <= 32768, abs(p.rotation) <= 3600 else { throw RenderError.invalid("Invalid clip properties.") }
                for (name, curve) in p.animations {
                    guard let range = ClipProperties.animationRanges[name] else { throw RenderError.invalid("Unknown animated property.") }
                    try Self.validateCurve(curve)
                    guard curve.keys.allSatisfy({ range.contains($0.value) }) else { throw RenderError.invalid("Keyframe value is outside the property range.") }
                }
                guard Set(clip.effects.map(\.id)).count == clip.effects.count else { throw RenderError.invalid("Duplicate effects.") }
                for effect in clip.effects {
                    try effect.mask?.validate()
                    try effect.keying?.validate()
                    guard effect.amount.isFinite, effect.kind.range.contains(effect.amount) else { throw RenderError.invalid("Effect value is out of range.") }
                    try Self.validateCurve(effect.animation)
                    guard effect.animation.keys.allSatisfy({ effect.kind.range.contains($0.value) }) else { throw RenderError.invalid("Effect keyframe is out of range.") }
                }
            }
        }
        if let storyline {
            guard let primary = tracks.first(where: { $0.id == storyline.trackID }), primary.kind == .video else { throw RenderError.invalid("The primary storyline must be a video track.") }
            let anchors = Dictionary(uniqueKeysWithValues: primary.clips.map { ($0.id,$0) })
            var end: Int64 = 0
            for clip in primary.clips.sorted(by: { $0.start < $1.start }) {
                guard clip.connection == nil, !storyline.enabled || clip.start == end else { throw RenderError.invalid("Magnetic storylines cannot contain implicit gaps.") }
                end = clip.end
            }
            for track in tracks where track.id != primary.id {
                for clip in track.clips {
                    if let connection = clip.connection {
                        guard let anchor = anchors[connection.anchor], abs(Double(connection.offset)) < 200_000_000,
                              clip.start == anchor.start + connection.offset else { throw RenderError.invalid("Invalid storyline connection.") }
                    }
                }
            }
        } else if tracks.flatMap(\.clips).contains(where: { $0.connection != nil }) {
            throw RenderError.invalid("Connected clips need a primary storyline.")
        }
        guard markers.allSatisfy({ $0.frame >= 0 && $0.frame < 100_000_000 }) else { throw RenderError.invalid("Invalid marker position.") }
    }
    private static func validateCurve(_ curve: AnimationCurve) throws {
        guard Set(curve.keys.map(\.frame)).count == curve.keys.count,
              Set(curve.keys.map(\.id)).count == curve.keys.count,
              curve.keys.allSatisfy({ $0.frame >= 0 && $0.frame < 200_000_000 && $0.value.isFinite }) else { throw RenderError.invalid("Invalid keyframe curve.") }
    }
}
