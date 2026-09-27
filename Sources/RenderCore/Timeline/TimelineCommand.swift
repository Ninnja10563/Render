import Foundation

public enum TrimEdge: Sendable { case leading, trailing }
public enum TimelineCommand: Sendable {
    case addAsset(MediaAsset)
    case addTrack(TrackKind)
    case append(asset: UUID, track: UUID, at: Int64)
    case insert(asset: UUID, track: UUID, at: Int64)
    case overwrite(asset: UUID, track: UUID, at: Int64)
    case rippleTrim(clip: UUID, edge: TrimEdge, to: Int64)
    case roll(clip: UUID, boundary: Int64)
    case slip(clip: UUID, delta: Int64)
    case slide(clip: UUID, delta: Int64)
    case detachAudio(clip: UUID)
    case deleteRange(track: UUID, start: Int64, end: Int64, ripple: Bool)
    case pasteLanes([ClipboardLane], at: Int64)
    case move(clips: Set<UUID>, delta: Int64)
    case moveToTrack(clip: UUID, track: UUID, at: Int64)
    case trim(clip: UUID, edge: TrimEdge, to: Int64)
    case split(clips: Set<UUID>, at: Int64)
    case delete(clips: Set<UUID>, ripple: Bool)
    case paste(clips: [TimelineClip], track: UUID, at: Int64)
    case properties(clip: UUID, ClipProperties)
    case effects(clip: UUID, [Effect])
    case animation(clip: UUID, target: AnimationTarget, edit: AnimationEdit)
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
        case .overwrite: return "Overwrite Edit"
        case .rippleTrim: return "Ripple Trim"
        case .roll: return "Roll Edit"
        case .slip: return "Slip Edit"
        case .slide: return "Slide Edit"
        case .detachAudio: return "Detach Audio"
        case .deleteRange: return "Delete Range"
        case .pasteLanes: return "Paste Clips"
        case .move, .moveToTrack: return "Move Clips"
        case .trim: return "Trim Clip"
        case .split: return "Split Clips"
        case .delete(_, let ripple): return ripple ? "Ripple Delete" : "Delete Clips"
        case .paste: return "Paste Clips"
        case .properties: return "Change Properties"
        case .effects: return "Change Effects"
        case .animation: return "Edit Keyframes"
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
        case .append(_,_,let frame), .insert(_,_,let frame), .overwrite(_,_,let frame), .moveToTrack(_,_,let frame),
             .rippleTrim(_,_,let frame), .roll(_,let frame), .pasteLanes(_,let frame),
             .trim(_,_,let frame), .split(_,let frame), .paste(_,_,let frame):
            guard frame >= 0, frame < 100_000_000 else { throw RenderError.invalid("Edit position is outside timeline bounds.") }
        default: break
        }
        var project = original
        let trackIndices = Dictionary(uniqueKeysWithValues: original.tracks.enumerated().map { ($0.element.id,$0.offset) })
        var clipLocations: [UUID: (track: Int, clip: Int)] = [:]
        for (t,track) in original.tracks.enumerated() {
            for (c,clip) in track.clips.enumerated() { clipLocations[clip.id] = (t,c) }
        }
        func trackIndex(_ id: UUID) throws -> Int {
            guard let index = trackIndices[id] else { throw RenderError.invalid("Track no longer exists.") }
            guard !project.tracks[index].locked else { throw RenderError.invalid("Unlock the track before editing it.") }
            return index
        }
        func location(_ id: UUID) throws -> (Int, Int) {
            guard let p = clipLocations[id] else { throw RenderError.invalid("Clip no longer exists.") }
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
        case .overwrite(let asset,let track,let at):
            let t = try trackIndex(track)
            let replacement = try newClip(asset,at)
            var remaining: [TimelineClip] = []
            for clip in project.tracks[t].clips {
                if clip.end <= at || clip.start >= replacement.end { remaining.append(clip); continue }
                if clip.start < at {
                    var left = clip; left.duration = at - clip.start; remaining.append(left)
                }
                if clip.end > replacement.end {
                    var right = clip
                    if clip.start < at { right.id = UUID() }
                    let delta = replacement.end - clip.start
                    right.sourceIn += project.settings.frameRate.seconds(delta) * clip.speed
                    right.animationOffset += delta; right.start = replacement.end
                    right.duration = clip.end - replacement.end; remaining.append(right)
                }
            }
            project.tracks[t].clips = remaining + [replacement]
        case .rippleTrim(let id,let edge,let frame):
            let (t,c) = try location(id)
            let original = project.tracks[t].clips[c]
            var edited = original
            let shift: Int64
            switch edge {
            case .leading:
                let delta = frame - original.start
                edited.sourceIn += project.settings.frameRate.seconds(delta) * original.speed
                edited.animationOffset += delta; edited.duration -= delta; shift = -delta
            case .trailing:
                shift = frame - original.end; edited.duration += shift
            }
            project.tracks[t].clips[c] = edited
            for index in project.tracks[t].clips.indices where index != c && project.tracks[t].clips[index].start >= original.end {
                project.tracks[t].clips[index].start += shift
            }
        case .roll(let id,let boundary):
            let (t,c) = try location(id)
            let left = project.tracks[t].clips[c]
            guard let n = project.tracks[t].clips.firstIndex(where: { $0.id != id && $0.start == left.end }) else { throw RenderError.invalid("Roll needs an adjacent clip on the right.") }
            let delta = boundary - left.end
            project.tracks[t].clips[c].duration += delta
            project.tracks[t].clips[n].start += delta
            project.tracks[t].clips[n].sourceIn += project.settings.frameRate.seconds(delta) * project.tracks[t].clips[n].speed
            project.tracks[t].clips[n].animationOffset += delta
            project.tracks[t].clips[n].duration -= delta
        case .slip(let id,let delta):
            guard abs(Double(delta)) < 100_000_000 else { throw RenderError.invalid("Slip exceeds timeline bounds.") }
            let (t,c) = try location(id)
            guard project.assets.first(where: { $0.id == project.tracks[t].clips[c].assetID })?.kind != .image else { throw RenderError.invalid("Still images do not have a moving source window.") }
            project.tracks[t].clips[c].sourceIn += project.settings.frameRate.seconds(delta) * project.tracks[t].clips[c].speed
        case .slide(let id,let delta):
            guard abs(Double(delta)) < 100_000_000 else { throw RenderError.invalid("Slide exceeds timeline bounds.") }
            let (t,c) = try location(id)
            let clip = project.tracks[t].clips[c]
            guard let before = project.tracks[t].clips.firstIndex(where: { $0.id != id && $0.end == clip.start }),
                  let after = project.tracks[t].clips.firstIndex(where: { $0.id != id && $0.start == clip.end }) else { throw RenderError.invalid("Slide needs adjacent clips on both sides.") }
            project.tracks[t].clips[before].duration += delta
            project.tracks[t].clips[c].start += delta
            project.tracks[t].clips[after].start += delta
            project.tracks[t].clips[after].sourceIn += project.settings.frameRate.seconds(delta) * project.tracks[t].clips[after].speed
            project.tracks[t].clips[after].animationOffset += delta
            project.tracks[t].clips[after].duration -= delta
        case .deleteRange(let track,let start,let end,let ripple):
            guard start >= 0, end > start, end < 100_000_000 else { throw RenderError.invalid("Select a valid timeline range.") }
            let t = try trackIndex(track)
            var remaining: [TimelineClip] = []
            for clip in project.tracks[t].clips {
                if clip.end <= start { remaining.append(clip); continue }
                if clip.start >= end {
                    var later = clip; if ripple { later.start -= end - start }; remaining.append(later); continue
                }
                if clip.start < start { var left = clip; left.duration = start - clip.start; remaining.append(left) }
                if clip.end > end {
                    var right = clip
                    if clip.start < start { right.id = UUID() }
                    right.sourceIn += project.settings.frameRate.seconds(end - clip.start) * clip.speed
                    right.animationOffset += end - clip.start
                    right.start = ripple ? start : end; right.duration = clip.end - end; remaining.append(right)
                }
            }
            project.tracks[t].clips = remaining
        case .detachAudio(let id):
            let (t,c) = try location(id)
            let clip = project.tracks[t].clips[c]
            guard let media = project.assets.first(where: { $0.id == clip.assetID }), media.kind == .video, media.audioChannels > 0 else { throw RenderError.invalid("This clip has no embedded audio to detach.") }
            var audioMedia = media; audioMedia.id = UUID(); audioMedia.kind = .audio
            audioMedia.name = media.name + " (audio)"
            project.assets.append(audioMedia)
            var audioClip = clip; audioClip.id = UUID(); audioClip.assetID = audioMedia.id
            audioClip.name = audioMedia.name; audioClip.effects = []; audioClip.properties = ClipProperties()
            audioClip.properties.volume = clip.properties.volume; audioClip.properties.muted = clip.properties.muted
            audioClip.properties.animations["volume"] = clip.properties.animations["volume"]
            var audioTrack = TimelineTrack(name: "Detached Audio",kind: .audio); audioTrack.clips = [audioClip]
            project.tracks.append(audioTrack)
            project.tracks[t].clips[c].properties.muted = true
        case .pasteLanes(let lanes,let at):
            let origin = lanes.flatMap(\.clips).map(\.start).min() ?? 0
            for lane in lanes {
                let t = try trackIndex(lane.trackID)
                project.tracks[t].clips += lane.clips.map { original in
                    var clip = original; clip.id = UUID(); clip.start = at + original.start - origin; return clip
                }
            }
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
        case .animation(let id, let target, let edit):
            let (t,c) = try location(id)
            let curve = try target.curve(in: project.tracks[t].clips[c])
            try target.replacingCurve(in: &project.tracks[t].clips[c], with: edit.applying(to: curve))
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
