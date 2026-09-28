import Foundation

public struct CameraAngle: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var assetID: UUID
    /// Camera source time corresponding to reference time zero.
    public var offset: Double
    public init(name: String,assetID: UUID,offset: Double = 0) { self.name = name; self.assetID = assetID; self.offset = offset }
}
public struct MulticamSource: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var angles: [CameraAngle]
    public init(name: String,angles: [CameraAngle]) { self.name = name; self.angles = angles }
    public func validate(assets: [UUID: MediaAsset]) throws {
        guard !name.isEmpty, name.utf8.count <= 1024, (2...16).contains(angles.count), Set(angles.map(\.id)).count == angles.count,
              Set(angles.map(\.assetID)).count == angles.count else { throw RenderError.invalid("A multicam source needs two to sixteen different cameras.") }
        for angle in angles {
            guard !angle.name.isEmpty, angle.name.utf8.count <= 1024, angle.offset.isFinite, abs(angle.offset) <= 604800,
                  assets[angle.assetID]?.kind == .video else { throw RenderError.invalid("Each camera needs valid video media and a finite synchronization offset.") }
        }
    }
}
public struct MulticamMembership: Codable, Equatable, Sendable {
    public var sourceID: UUID
    public var angleID: UUID
    public init(sourceID: UUID,angleID: UUID) { self.sourceID = sourceID; self.angleID = angleID }
}

public enum MulticamEditing {
    public static func replacingAngle(in clip: TimelineClip,with angleID: UUID,source: MulticamSource) throws -> TimelineClip {
        guard let membership = clip.multicam, membership.sourceID == source.id,
              let old = source.angles.first(where: { $0.id == membership.angleID }), let next = source.angles.first(where: { $0.id == angleID }) else { throw RenderError.invalid("The requested camera angle no longer exists.") }
        var result = clip
        result.sourceIn = clip.sourceIn - old.offset + next.offset
        guard result.sourceIn >= 0 else { throw RenderError.invalid("That camera had not started recording at this edit point.") }
        result.assetID = next.assetID; result.multicam?.angleID = next.id
        result.name = source.name + " · " + next.name
        return result
    }
}
