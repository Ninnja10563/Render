import Foundation

public struct StorylineSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var trackID: UUID
    public init(enabled: Bool,trackID: UUID) { self.enabled = enabled; self.trackID = trackID }
}
public struct ClipConnection: Codable, Equatable, Sendable {
    public var anchor: UUID
    public var offset: Int64
    public init(anchor: UUID,offset: Int64) { self.anchor = anchor; self.offset = offset }
}

public enum MagneticEditing {
    /// Reconcile primary order and connected timing after an edit, before transaction validation.
    static func reconcile(_ project: inout RenderProject,from original: RenderProject) throws {
        guard let settings = project.storyline, let primary = project.tracks.firstIndex(where: { $0.id == settings.trackID }) else { return }
        if settings.enabled {
            let sorted = project.tracks[primary].clips.enumerated().sorted {
                $0.element.start == $1.element.start ? $0.offset < $1.offset : $0.element.start < $1.element.start
            }.map(\.element)
            var cursor: Int64 = 0, packed: [TimelineClip] = []
            for var clip in sorted {
                guard clip.duration > 0, clip.duration < 100_000_000, cursor < 100_000_000 else { throw RenderError.invalid("Storyline exceeds timeline bounds.") }
                clip.start = cursor; cursor += clip.duration; clip.connection = nil; packed.append(clip)
            }
            if project.tracks[primary].locked && packed.contains(where: { packedClip in project.tracks[primary].clips.first(where: { $0.id == packedClip.id })?.start != packedClip.start }) { throw RenderError.invalid("Unlock the storyline before rippling it.") }
            project.tracks[primary].clips = packed
        }
        let remainingIDs = Set(project.tracks.flatMap(\.clips).map(\.id))
        let anchors = Dictionary(uniqueKeysWithValues: project.tracks[primary].clips.map { ($0.id,$0) })
        let oldClips = Dictionary(uniqueKeysWithValues: original.tracks.flatMap(\.clips).map { ($0.id,$0) })
        for t in project.tracks.indices where t != primary {
            var retained: [TimelineClip] = []
            for var clip in project.tracks[t].clips {
                if let connection = clip.connection {
                    guard let anchor = anchors[connection.anchor] else {
                        if settings.enabled && oldClips[connection.anchor] != nil && !remainingIDs.contains(connection.anchor) {
                            guard !project.tracks[t].locked else { throw RenderError.invalid("A connected clip is locked. Unlock its track before deleting the anchor.") }
                            continue
                        }
                        clip.connection = nil; retained.append(clip); continue
                    }
                    if let oldAnchor = oldClips[connection.anchor], oldAnchor.start != anchor.start || oldAnchor.animationOffset != anchor.animationOffset {
                        let offset = connection.offset - (anchor.animationOffset - oldAnchor.animationOffset)
                        let newStart = max(0,anchor.start + offset)
                        if newStart != clip.start && project.tracks[t].locked { throw RenderError.invalid("A connected clip is locked. Unlock its track before moving the anchor.") }
                        clip.start = newStart
                        clip.connection = ClipConnection(anchor: anchor.id,offset: newStart - anchor.start)
                    } else {
                        clip.connection = ClipConnection(anchor: anchor.id,offset: clip.start - anchor.start)
                    }
                } else if settings.enabled && oldClips[clip.id] == nil && !anchors.isEmpty {
                    let ordered = anchors.values.sorted { $0.start < $1.start }
                    if let anchor = ordered.last(where: { $0.start <= clip.start }) ?? ordered.first {
                        clip.connection = ClipConnection(anchor: anchor.id,offset: clip.start - anchor.start)
                    }
                }
                retained.append(clip)
            }
            project.tracks[t].clips = retained
        }
        // Clips moved onto the primary storyline cease being connected clips.
        for c in project.tracks[primary].clips.indices { project.tracks[primary].clips[c].connection = nil }
    }
    static func moveStoryline(_ ids: Set<UUID>,delta: Int64,project: inout RenderProject) -> Set<UUID> {
        guard let settings = project.storyline, settings.enabled,
              let t = project.tracks.firstIndex(where: { $0.id == settings.trackID }) else { return [] }
        let selected = project.tracks[t].clips.filter { ids.contains($0.id) }.sorted { $0.start < $1.start }
        guard let first = selected.first else { return [] }
        let total = selected.reduce(Int64(0)) { $0 + $1.duration }
        let targetCenter = Double(first.start) + Double(delta) + Double(total) / 2
        var ordered = project.tracks[t].clips.filter { !ids.contains($0.id) }.sorted { $0.start < $1.start }
        let position = ordered.firstIndex { delta < 0 ? Double($0.start) + Double($0.duration) / 2 >= targetCenter : Double($0.start) + Double($0.duration) / 2 > targetCenter } ?? ordered.count
        ordered.insert(contentsOf: selected,at: position)
        var cursor: Int64 = 0
        for c in ordered.indices { ordered[c].start = cursor; cursor += ordered[c].duration }
        project.tracks[t].clips = ordered
        return Set(selected.map(\.id))
    }
}
