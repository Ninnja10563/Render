import Foundation

public enum TrimEdge: Sendable { case leading, trailing }
public enum TimelineCommand: Sendable {
    case makeMulticam(clip: UUID,MulticamSource)
    case switchAngle(clip: UUID,angle: UUID,at: Int64?)
    case transition(clip: UUID,ClipTransition?)
    case storyline(enabled: Bool,track: UUID)
    case connection(clip: UUID,anchor: UUID?)
    case gap(track: UUID,at: Int64,duration: Int64)
    case addTitle(TitleContent,at: Int64,duration: Int64)
    case title(clip: UUID,TitleContent)
    case captions([CaptionCue])
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
    case mediaVariant(asset: UUID, MediaVariant)
    case relink(asset: UUID, URL)

    public var label: String {
        switch self {
        case .makeMulticam: return "Create Multicam Source"
        case .switchAngle: return "Switch Camera Angle"
        case .transition: return "Change Transition"
        case .storyline: return "Change Timeline Mode"
        case .connection: return "Change Clip Connection"
        case .gap: return "Insert Gap"
        case .addTitle: return "Add Title"
        case .title: return "Edit Title"
        case .captions: return "Import Captions"
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
        case .mediaVariant: return "Attach Generated Media"
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
        func reconnectSplit(_ old: TimelineClip,right: TimelineClip,cut: Int64) throws {
            for t in project.tracks.indices {
                for c in project.tracks[t].clips.indices {
                    let child = project.tracks[t].clips[c]
                    guard child.connection?.anchor == old.id, child.start >= cut else { continue }
                    let offset = child.start - cut
                    let newStart = right.start + offset
                    guard !project.tracks[t].locked || newStart == child.start else { throw RenderError.invalid("Unlock connected clips before inserting at this position.") }
                    project.tracks[t].clips[c].connection = ClipConnection(anchor: right.id,offset: offset)
                    project.tracks[t].clips[c].start = newStart
                }
            }
        }
        switch self {
        case .makeMulticam(let id,let source):
            let (t,c) = try location(id)
            let clip = project.tracks[t].clips[c]
            guard project.tracks[t].kind == .video, clip.multicam == nil, let angle = source.angles.first(where: { $0.assetID == clip.assetID }), angle.offset == 0 else { throw RenderError.invalid("Choose a normal video clip as the zero-offset reference camera.") }
            project.multicamSources = (project.multicamSources ?? []) + [source]
            project.tracks[t].clips[c].multicam = MulticamMembership(sourceID: source.id,angleID: angle.id)
            project.tracks[t].clips[c].name = source.name + " · " + angle.name
        case .switchAngle(let id,let angle,let cut):
            let (t,c) = try location(id)
            let originalClip = project.tracks[t].clips[c]
            guard let membership = originalClip.multicam, let source = project.multicamSources?.first(where: { $0.id == membership.sourceID }) else { throw RenderError.invalid("Select a multicam clip first.") }
            if angle == membership.angleID { break }
            if let cut {
                guard cut >= originalClip.start, cut < originalClip.end else { throw RenderError.invalid("Place the playhead inside the selected multicam clip.") }
                if cut > originalClip.start {
                    let delta = cut - originalClip.start
                    var right = originalClip; right.id = UUID(); right.start = cut; right.duration -= delta
                    right.sourceIn += project.settings.frameRate.seconds(delta) * right.speed; right.animationOffset += delta
                    right = try MulticamEditing.replacingAngle(in: right,with: angle,source: source)
                    project.tracks[t].clips[c].duration = delta; project.tracks[t].clips[c].transition = nil
                    project.tracks[t].clips.append(right)
                    try reconnectSplit(originalClip,right: right,cut: cut)
                } else { project.tracks[t].clips[c] = try MulticamEditing.replacingAngle(in: originalClip,with: angle,source: source) }
            } else { project.tracks[t].clips[c] = try MulticamEditing.replacingAngle(in: originalClip,with: angle,source: source) }
        case .transition(let id,let transition):
            let (t,c) = try location(id)
            guard project.tracks[t].kind == .video else { throw RenderError.invalid("Select a video clip for a transition.") }
            project.tracks[t].clips[c].transition = transition
        case .storyline(let enabled,let track):
            let t = try trackIndex(track)
            guard project.tracks[t].kind == .video else { throw RenderError.invalid("Choose a video track for the storyline.") }
            if project.storyline?.trackID != track {
                for t in project.tracks.indices { for c in project.tracks[t].clips.indices { project.tracks[t].clips[c].connection = nil } }
            }
            project.storyline = StorylineSettings(enabled: enabled,trackID: track)
        case .connection(let id,let anchorID):
            let (t,c) = try location(id)
            if let anchorID {
                guard let settings = project.storyline, project.tracks[t].id != settings.trackID,
                      let primary = project.tracks.first(where: { $0.id == settings.trackID }), let anchor = primary.clips.first(where: { $0.id == anchorID }) else { throw RenderError.invalid("Connect a clip to an existing primary storyline clip.") }
                project.tracks[t].clips[c].connection = ClipConnection(anchor: anchorID,offset: project.tracks[t].clips[c].start - anchor.start)
            } else { project.tracks[t].clips[c].connection = nil }
        case .gap(let track,let at,let duration):
            guard at >= 0, at < 100_000_000, duration > 0, duration < 100_000_000 else { throw RenderError.invalid("Invalid gap timing.") }
            let t = try trackIndex(track)
            var gap = TimelineClip(assetID: nil,name: "Gap",start: at,duration: duration); gap.isGap = true
            var clips: [TimelineClip] = []
            for var clip in project.tracks[t].clips {
                if clip.start < at && clip.end > at {
                    var right = clip; right.id = UUID(); right.start = at + duration
                    right.sourceIn += project.settings.frameRate.seconds(at - clip.start) * clip.speed
                    right.animationOffset += at - clip.start; right.duration = clip.end - at
                    try reconnectSplit(clip,right: right,cut: at)
                    clip.duration = at - clip.start; clips.append(right)
                } else if clip.start >= at { clip.start += duration }
                clips.append(clip)
            }
            project.tracks[t].clips = clips + [gap]
        case .addTitle(let title,let start,let duration):
            var track = TimelineTrack(name: title.role == .caption ? "Captions" : "Titles",kind: .video)
            var clip = TimelineClip(assetID: nil,name: title.text,start: start,duration: duration); clip.title = title
            if title.role == .caption { clip.properties.y = -Double(project.settings.height) * 0.35 }
            track.clips = [clip]; project.tracks.insert(track,at: 0)
        case .title(let id,let content):
            let (t,c) = try location(id)
            guard project.tracks[t].clips[c].title != nil else { throw RenderError.invalid("Select a title or caption clip.") }
            project.tracks[t].clips[c].title = content; project.tracks[t].clips[c].name = String(content.text.prefix(80))
        case .captions(let cues):
            var lanes: [TimelineTrack] = []
            for cue in cues.sorted(by: { $0.start < $1.start }) {
                guard cue.start >= 0, cue.end > cue.start, cue.end < 100_000_000 else { throw RenderError.invalid("Invalid caption timing.") }
                var title = TitleContent(text: cue.text,role: .caption); title.fontSize = Double(project.settings.height) * 0.045
                title.background = RGBAColor(0,0,0,0.65); title.shadowBlur = 0
                var clip = TimelineClip(assetID: nil,name: String(cue.text.prefix(80)),start: cue.start,duration: cue.end - cue.start)
                clip.title = title; clip.properties.y = -Double(project.settings.height) * 0.35
                if let lane = lanes.firstIndex(where: { ($0.clips.last?.end ?? 0) <= cue.start }) { lanes[lane].clips.append(clip) }
                else { var lane = TimelineTrack(name: "Captions \(lanes.count + 1)",kind: .video); lane.clips = [clip]; lanes.append(lane) }
            }
            project.tracks.insert(contentsOf: lanes,at: 0)
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
                    try reconnectSplit(clip,right: right,cut: at)
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
            guard project.tracks[t].clips[c].assetID != nil, project.tracks[t].clips[c].title == nil, project.assets.first(where: { $0.id == project.tracks[t].clips[c].assetID })?.kind != .image else { throw RenderError.invalid("Still images do not have a moving source window.") }
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
            var audioMedia = media; audioMedia.id = UUID(); audioMedia.kind = .audio; audioMedia.variants = nil
            audioMedia.name = media.name + " (audio)"
            project.assets.append(audioMedia)
            var audioClip = clip; audioClip.id = UUID(); audioClip.assetID = audioMedia.id
            audioClip.name = audioMedia.name; audioClip.effects = []; audioClip.transition = nil; audioClip.multicam = nil; audioClip.properties = ClipProperties()
            audioClip.properties.volume = clip.properties.volume; audioClip.properties.muted = clip.properties.muted
            audioClip.properties.animations["volume"] = clip.properties.animations["volume"]
            var audioTrack = TimelineTrack(name: "Detached Audio",kind: .audio); audioTrack.clips = [audioClip]
            project.tracks.append(audioTrack)
            project.tracks[t].clips[c].properties.muted = true
        case .pasteLanes(let lanes,let at):
            let sourceIDs = lanes.flatMap(\.clips).map(\.id)
            guard Set(sourceIDs).count == sourceIDs.count else { throw RenderError.invalid("Clipboard contains duplicate clips.") }
            let copiedIDs = Dictionary(uniqueKeysWithValues: sourceIDs.map { ($0,UUID()) })
            let origin = lanes.flatMap(\.clips).map(\.start).min() ?? 0
            for lane in lanes {
                let t = try trackIndex(lane.trackID)
                project.tracks[t].clips += lane.clips.map { original in
                    var clip = original; clip.id = copiedIDs[original.id]!; clip.start = at + original.start - origin
                    if let connection = clip.connection, let anchor = copiedIDs[connection.anchor] { clip.connection = ClipConnection(anchor: anchor,offset: connection.offset) }
                    if let transition = clip.transition, let right = copiedIDs[transition.rightID] { clip.transition?.rightID = right }
                    return clip
                }
            }
        case .move(let ids, let delta):
            guard abs(Double(delta)) < 100_000_000 else { throw RenderError.invalid("Move exceeds timeline bounds.") }
            for id in ids { _ = try location(id) }
            let moved = MagneticEditing.moveStoryline(ids,delta: delta,project: &project)
            for id in ids.subtracting(moved) {
                let (t,c) = try location(id)
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
                try reconnectSplit(project.tracks[t].clips[c],right: right,cut: at)
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
            guard Set(clips.map(\.id)).count == clips.count else { throw RenderError.invalid("Clipboard contains duplicate clips.") }
            let copiedIDs = Dictionary(uniqueKeysWithValues: clips.map { ($0.id,UUID()) })
            let origin = clips.map(\.start).min() ?? 0
            project.tracks[t].clips += clips.map { source in
                var clip = source; clip.id = copiedIDs[source.id]!; clip.start = at + source.start - origin
                if let transition = clip.transition, let right = copiedIDs[transition.rightID] { clip.transition?.rightID = right }
                return clip
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
        case .mediaVariant(let id,let variant):
            guard let a = project.assets.firstIndex(where: { $0.id == id }), project.assets[a].url.standardizedFileURL == variant.source.url else { throw RenderError.invalid("The source changed while media was being generated.") }
            var variants = project.assets[a].variants ?? []
            variants.removeAll { $0.mode == variant.mode }; variants.append(variant)
            project.assets[a].variants = variants
        case .relink(let id, let url):
            guard let a = project.assets.firstIndex(where: { $0.id == id }) else { throw RenderError.invalid("Media no longer exists.") }
            project.assets[a].url = url
            project.assets[a].variants = nil
        }
        try MagneticEditing.reconcile(&project,from: original)
        if case .transition = self { /* Explicit authoring reports invalid handles instead of discarding the request. */ }
        else { TransitionEditing.reconcile(&project) }
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
