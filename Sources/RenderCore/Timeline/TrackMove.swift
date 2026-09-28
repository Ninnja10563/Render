import Foundation

/// A drag snapshot holds references to value-semantic clips; pointer movement never edits the project.
public struct TrackMovePlan: Sendable {
    public struct Placement: Identifiable, Sendable {
        public var id: UUID { clip.id }
        public let clip: TimelineClip
        public let sourceTrack: Int
        public let targetTrack: Int
        public let start: Int64
    }
    private let tracks: [TimelineTrack]
    private let selected: Set<UUID>
    private let entries: [(track: Int,clip: TimelineClip)]
    private let primary: UUID?
    private let stationary: [[TimelineClip]]
    public let earliest: Int64
    public init(project: RenderProject,clips: Set<UUID>) throws {
        tracks = project.tracks; selected = clips
        primary = project.storyline?.enabled == true ? project.storyline?.trackID : nil
        entries = project.tracks.enumerated().flatMap { index,track in
            track.clips.filter { clips.contains($0.id) || $0.connection.map { clips.contains($0.anchor) } == true }.map { (index,$0) }
        }
        guard !clips.isEmpty, clips.isSubset(of: Set(entries.map { $0.clip.id })) else { throw RenderError.invalid("Select existing clips to move.") }
        earliest = entries.map { $0.clip.start }.min() ?? 0
        let moving = Set(entries.map { $0.clip.id })
        stationary = project.tracks.map { $0.clips.filter { !moving.contains($0.id) }.sorted { $0.start < $1.start } }
    }
    public func placements(delta: Int64,trackOffset: Int) throws -> [Placement] {
        guard abs(Double(delta)) < 100_000_000, abs(Double(trackOffset)) < Double(tracks.count) else { throw RenderError.invalid("Drop within the existing timeline tracks.") }
        let result = try entries.map { entry in
            let target = entry.track + (selected.contains(entry.clip.id) ? trackOffset : 0)
            guard tracks.indices.contains(target), tracks[target].kind == tracks[entry.track].kind else { throw RenderError.invalid("Move each clip onto a matching video or audio track.") }
            guard !tracks[entry.track].locked, !tracks[target].locked else { throw RenderError.invalid("Unlock source and destination tracks before moving clips.") }
            let start = entry.clip.start + delta
            guard start >= 0, start + entry.clip.duration < 100_000_000 else { throw RenderError.invalid("Move exceeds timeline bounds.") }
            // The primary storyline packs on commit. Other tracks must have room for the entire selection.
            if tracks[target].id != primary {
                let intervals = stationary[target]
                var low = 0,high = intervals.count
                while low < high { let mid = (low + high) / 2; if intervals[mid].end <= start { low = mid + 1 } else { high = mid } }
                guard low == intervals.count || intervals[low].start >= start + entry.clip.duration else { throw RenderError.invalid("The destination overlaps another clip.") }
            }
            return Placement(clip: entry.clip,sourceTrack: entry.track,targetTrack: target,start: start)
        }
        let byTrack = Dictionary(grouping: result,by: \.targetTrack)
        for (target,positions) in byTrack where tracks[target].id != primary {
            let sorted = positions.sorted { $0.start < $1.start }
            for index in sorted.indices.dropFirst() where sorted[index - 1].start + sorted[index - 1].clip.duration > sorted[index].start {
                throw RenderError.invalid("The moved clips would overlap each other.")
            }
        }
        return result
    }
    static func apply(_ ids: Set<UUID>,delta: Int64,trackOffset: Int,to project: inout RenderProject) throws {
        let positions = try TrackMovePlan(project: project,clips: ids).placements(delta: delta,trackOffset: trackOffset)
        let movedIDs = Set(positions.map(\.id))
        for t in project.tracks.indices { project.tracks[t].clips.removeAll { movedIDs.contains($0.id) } }
        for position in positions {
            var clip = position.clip; clip.start = position.start
            project.tracks[position.targetTrack].clips.append(clip)
        }
    }
}
