import Foundation

public struct CompoundSource: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var kind: TrackKind
    public var settings: ProjectSettings
    public var duration: Int64
    public var tracks: [TimelineTrack]
    public var markers: [TimelineMarker] = []
    public var storyline: StorylineSettings?
    public init(name: String,kind: TrackKind,settings: ProjectSettings,duration: Int64,tracks: [TimelineTrack]) {
        self.name = name; self.kind = kind; self.settings = settings; self.duration = duration; self.tracks = tracks
    }
    public var seconds: Double { settings.frameRate.seconds(duration) }
}

extension RenderProject {
    /// A reusable source DAG, bounded independently from the compositor's defensive limit.
    func validateCompoundGraph(_ sources: [UUID: CompoundSource]) throws {
        var visiting: Set<UUID> = [], depths: [UUID: Int] = [:]
        func depth(_ id: UUID) throws -> Int {
            if let value = depths[id] { return value }
            guard let source = sources[id] else { throw RenderError.invalid("A compound source is missing.") }
            guard visiting.insert(id).inserted else { throw RenderError.invalid("A compound cannot contain itself, directly or indirectly.") }
            guard visiting.count <= 8 else { throw RenderError.invalid("Compound nesting is limited to eight levels.") }
            var result = 1
            for child in source.tracks.flatMap(\.clips).compactMap(\.compoundID) { result = max(result,1 + (try depth(child))) }
            guard result <= 8 else { throw RenderError.invalid("Compound nesting is limited to eight levels.") }
            visiting.remove(id); depths[id] = result; return result
        }
        for id in sources.keys { _ = try depth(id) }
    }
    public func timelineContext(compoundID: UUID) throws -> RenderProject {
        try validate()
        guard let source = compounds?.first(where: { $0.id == compoundID }) else { throw RenderError.invalid("Compound source no longer exists.") }
        let lookup = Dictionary(uniqueKeysWithValues: (compounds ?? []).map { ($0.id,$0) })
        var reachable: Set<UUID> = []
        func collect(_ tracks: [TimelineTrack]) {
            for id in tracks.flatMap(\.clips).compactMap(\.compoundID) where reachable.insert(id).inserted {
                if let child = lookup[id] { collect(child.tracks) }
            }
        }
        collect(source.tracks)
        var result = self
        result.name = source.name; result.settings = source.settings; result.tracks = source.tracks
        result.markers = source.markers; result.storyline = source.storyline
        result.compounds = (compounds ?? []).filter { reachable.contains($0.id) }
        return result
    }
    public func replacingContext(_ context: RenderProject,compoundID: UUID) throws -> RenderProject {
        try context.validate()
        guard let index = compounds?.firstIndex(where: { $0.id == compoundID }) else { throw RenderError.invalid("Compound source no longer exists.") }
        var result = self
        result.assets = context.assets; result.multicamSources = context.multicamSources
        result.compounds![index].name = context.name; result.compounds![index].settings = context.settings
        result.compounds![index].tracks = context.tracks; result.compounds![index].markers = context.markers
        result.compounds![index].storyline = context.storyline
        result.compounds![index].duration = max(result.compounds![index].duration,context.duration)
        for source in context.compounds ?? [] {
            if let existing = result.compounds!.firstIndex(where: { $0.id == source.id }) { result.compounds![existing] = source }
            else { result.compounds!.append(source) }
        }
        try result.validate(); return result
    }
}
