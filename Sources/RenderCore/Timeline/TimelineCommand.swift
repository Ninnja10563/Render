import Foundation

public enum TrimEdge: Sendable { case leading, trailing }
public enum TimelineCommand: Sendable {
    case addAsset(MediaAsset)
    case addTrack(TrackKind)
    case append(asset: UUID, track: UUID, at: Int64)
    case insert(asset: UUID, track: UUID, at: Int64)
    case move(clips: Set<UUID>, delta: Int64)
    case moveToTrack(clip: UUID, track: UUID, at: Int64)
    case trim(clip: UUID, edge: TrimEdge, to: Int64)
    case split(clips: Set<UUID>, at: Int64)
    case delete(clips: Set<UUID>, ripple: Bool)
    case paste(clips: [TimelineClip], track: UUID, at: Int64)
    case properties(clip: UUID, ClipProperties)
    case effects(clip: UUID, [Effect])
    case speed(clip: UUID, Double)
    case trackState(track: UUID, locked: Bool, hidden: Bool, muted: Bool, solo: Bool)
    case marker(TimelineMarker)
    case removeMarker(UUID)
    case relink(asset: UUID, URL)

    public var label: String {
        switch self {
        case .addAsset: return "Import Media"
        case .addTrack: return "Add Track"
        case .append: return "Add Clip"
        case .insert: return "Insert Clip"
        case .move, .moveToTrack: return "Move Clips"
        case .trim: return "Trim Clip"
        case .split: return "Split Clips"
        case .delete(_, let ripple): return ripple ? "Ripple Delete" : "Delete Clips"
        case .paste: return "Paste Clips"
        case .properties: return "Change Properties"
        case .effects: return "Change Effects"
        case .speed: return "Change Speed"
        case .trackState: return "Change Track"
        case .marker: return "Add Marker"
        case .removeMarker: return "Delete Marker"
        case .relink: return "Relink Media"
        }
    }
    public func applying(to original: RenderProject) throws -> RenderProject {
        try original.validate()
        switch self {
        case .append(_,_,let frame), .insert(_,_,let frame), .moveToTrack(_,_,let frame),
             .trim(_,_,let frame), .split(_,let frame), .paste(_,_,let frame):
            guard frame >= 0, frame < 100_000_000 else { throw RenderError.invalid("Edit position is outside timeline bounds.") }
        default: break
        }
        var project = original
        func trackIndex(_ id: UUID) throws -> Int {
            guard let index = project.tracks.firstIndex(where: { $0.id == id }) else { throw RenderError.invalid("Track no longer exists.") }
            guard !project.tracks[index].locked else { throw RenderError.invalid("Unlock the track before editing it.") }
            return index
        }
        func location(_ id: UUID) throws -> (Int, Int) {
            guard let p = project.location(id) else { throw RenderError.invalid("Clip no longer exists.") }
            _ = try trackIndex(project.tracks[p.track].id)
            return (p.track, p.clip)
        }
        func newClip(_ assetID: UUID, _ at: Int64) throws -> TimelineClip {
            guard let asset = project.assets.first(where: { $0.id == assetID }) else { throw RenderError.invalid("Select valid media first.") }
            let frames = asset.kind == .image ? project.settings.frameRate.frames(5) : Int64((asset.duration * project.settings.frameRate.value).rounded(.down))
            return TimelineClip(assetID: asset.id, name: asset.name, start: at, duration: max(1, frames))
        }
        switch self {
        case .addAsset(let asset):
            project.assets.append(asset)
        case .addTrack(let kind):
            let count = project.tracks.filter { $0.kind == kind }.count + 1
            let track = TimelineTrack(name: "\(kind == .video ? "Video" : "Audio") \(count)", kind: kind)
            if kind == .video { project.tracks.insert(track, at: 0) } else { project.tracks.append(track) }
        case .append(let asset, let track, let at):
            let t = try trackIndex(track)
            project.tracks[t].clips.append(try newClip(asset, at))
        case .insert(let asset, let track, let at):
            let t = try trackIndex(track)
            let inserted = try newClip(asset, at)
            var clips: [TimelineClip] = []
            for var clip in project.tracks[t].clips {
                if clip.start < at && clip.end > at {
                    var right = clip
                    right.id = UUID(); right.start = at + inserted.duration
                    right.sourceIn += project.settings.frameRate.seconds(at - clip.start) * clip.speed
                    right.animationOffset += at - clip.start
                    right.duration = clip.end - at
                    clip.duration = at - clip.start
                    clips.append(right)
                } else if clip.start >= at { clip.start += inserted.duration }
                clips.append(clip)
            }
            project.tracks[t].clips = clips + [inserted]
        case .move(let ids, let delta):
            guard abs(Double(delta)) < 100_000_000 else { throw RenderError.invalid("Move exceeds timeline bounds.") }
            for id in ids {
                let (t, c) = try location(id)
                project.tracks[t].clips[c].start += delta
            }
        case .moveToTrack(let id, let track, let at):
            let target = try trackIndex(track)
            let (t, c) = try location(id)
            var clip = project.tracks[t].clips.remove(at: c)
            clip.start = at
            project.tracks[target].clips.append(clip)
        case .trim(let id, let edge, let frame):
            let (t, c) = try location(id)
            var clip = project.tracks[t].clips[c]
            switch edge {
            case .leading:
                let delta = frame - clip.start
                clip.sourceIn += project.settings.frameRate.seconds(delta) * clip.speed
                clip.animationOffset += delta
                clip.duration -= delta; clip.start = frame
            case .trailing: clip.duration = frame - clip.start
            }
            project.tracks[t].clips[c] = clip
        case .split(let ids, let at):
            for id in ids {
                let (t, c) = try location(id)
                var right = project.tracks[t].clips[c]
                guard at > right.start && at < right.end else { continue }
                let leftDuration = at - right.start
                right.id = UUID(); right.start = at; right.duration -= leftDuration
                right.sourceIn += project.settings.frameRate.seconds(leftDuration) * right.speed
                right.animationOffset += leftDuration
                project.tracks[t].clips[c].duration = leftDuration
                project.tracks[t].clips.append(right)
            }
        case .delete(let ids, let ripple):
            for id in ids { _ = try location(id) }
            for t in project.tracks.indices {
                let removed = project.tracks[t].clips.filter { ids.contains($0.id) }
                project.tracks[t].clips.removeAll { ids.contains($0.id) }
                if ripple {
                    for c in project.tracks[t].clips.indices {
                        let start = project.tracks[t].clips[c].start
                        project.tracks[t].clips[c].start -= removed.filter { $0.end <= start }.reduce(0) { $0 + $1.duration }
                    }
                }
            }
        case .paste(let clips, let track, let at):
            let t = try trackIndex(track)
            let origin = clips.map(\.start).min() ?? 0
            project.tracks[t].clips += clips.map { source in
                var clip = source; clip.id = UUID(); clip.start = at + source.start - origin; return clip
            }
        case .properties(let id, let properties):
            let (t, c) = try location(id); project.tracks[t].clips[c].properties = properties
        case .effects(let id, let effects):
            let (t, c) = try location(id); project.tracks[t].clips[c].effects = effects
        case .speed(let id, let speed):
            guard speed.isFinite, (0.05...16).contains(speed) else { throw RenderError.invalid("Speed must be between 5% and 1600%.") }
            let (t, c) = try location(id)
            let old = project.tracks[t].clips[c]
            project.tracks[t].clips[c].duration = max(1, Int64((Double(old.duration) * old.speed / speed).rounded(.down)))
            project.tracks[t].clips[c].speed = speed
        case .trackState(let id, let locked, let hidden, let muted, let solo):
            guard let t = project.tracks.firstIndex(where: { $0.id == id }) else { throw RenderError.invalid("Track no longer exists.") }
            project.tracks[t].locked = locked; project.tracks[t].hidden = hidden
            project.tracks[t].muted = muted; project.tracks[t].solo = solo
        case .marker(let marker): project.markers.append(marker)
        case .removeMarker(let id): project.markers.removeAll { $0.id == id }
        case .relink(let id, let url):
            guard let a = project.assets.firstIndex(where: { $0.id == id }) else { throw RenderError.invalid("Media no longer exists.") }
            project.assets[a].url = url
        }
        try project.validate()
        return project
    }
}

/// A committed transaction also supplies the exact inverse used by the UI's UndoManager.
public struct ProjectTransaction: Sendable {
    public let name: String
    public let before: RenderProject
    public let after: RenderProject
    public init(_ command: TimelineCommand, project: RenderProject) throws {
        name = command.label; before = project; after = try command.applying(to: project)
    }
}

public enum TimelineSnap {
    public static func frame(_ proposed: Int64, targets: [Int64], threshold: Int64) -> Int64 {
        guard let nearest = targets.min(by: { abs(Double($0) - Double(proposed)) < abs(Double($1) - Double(proposed)) }),
              abs(Double(nearest) - Double(proposed)) <= Double(threshold) else { return proposed }
        return nearest
    }
}
