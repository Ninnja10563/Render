import Foundation

public enum CompoundEditing {
    public static func create(_ selected: Set<UUID>,name: String,in original: RenderProject) throws -> RenderProject {
        try original.validate()
        guard !selected.isEmpty, !name.isEmpty else { throw RenderError.invalid("Select clips and name the compound.") }
        var chosen = selected
        for clip in original.tracks.flatMap(\.clips) where clip.connection.map({ selected.contains($0.anchor) }) == true { chosen.insert(clip.id) }
        let clips = original.tracks.flatMap(\.clips).filter { chosen.contains($0.id) }
        guard clips.count == chosen.count, let start = clips.map(\.start).min(), let end = clips.map(\.end).max() else { throw RenderError.invalid("Some selected clips no longer exist.") }
        let selectedTracks = original.tracks.indices.filter { original.tracks[$0].clips.contains { chosen.contains($0.id) } }
        guard selectedTracks.allSatisfy({ !original.tracks[$0].locked }) else { throw RenderError.invalid("Unlock all selected and connected tracks before creating a compound.") }
        for track in original.tracks {
            for clip in track.clips {
                if let transition = clip.transition, chosen.contains(clip.id) != chosen.contains(transition.rightID) { throw RenderError.invalid("Include both sides of a transition when creating a compound.") }
            }
        }
        let videoIndices = selectedTracks.filter { original.tracks[$0].kind == .video }
        if let first = videoIndices.first, let last = videoIndices.last {
            guard original.tracks[first...last].flatMap(\.clips).allSatisfy({ chosen.contains($0.id) || $0.end <= start || $0.start >= end }) else { throw RenderError.invalid("Include intervening video clips to preserve the compositing order.") }
        }
        let primaryIndex = original.storyline.flatMap { settings in selectedTracks.first { original.tracks[$0].id == settings.trackID } }
        if let primaryIndex {
            let track = original.tracks[primaryIndex]
            guard !track.hidden, !track.muted, !original.tracks.contains(where: \.solo) else { throw RenderError.invalid("Show and unmute the primary track, and clear solos, before grouping a storyline.") }
            let primaryClips = track.clips.filter { chosen.contains($0.id) }
            if original.storyline?.enabled == true {
                guard primaryClips.map(\.start).min() == start, primaryClips.map(\.end).max() == end else { throw RenderError.invalid("Connected clips must fit the selected storyline span. Extend the selection or use traditional mode.") }
            }
        }
        var children: [TimelineTrack] = [], childPrimary: UUID?
        for index in selectedTracks {
            var track = original.tracks[index]; track.id = UUID(); track.locked = false
            if index == primaryIndex { childPrimary = track.id }
            track.clips = track.clips.filter { chosen.contains($0.id) }.map { value in
                var clip = value; clip.start -= start
                if clip.connection.map({ !chosen.contains($0.anchor) }) == true { clip.connection = nil }
                return clip
            }
            children.append(track)
        }
        var source = CompoundSource(name: name,kind: videoIndices.isEmpty ? .audio : .video,settings: original.settings,duration: end - start,tracks: children)
        if let childPrimary { source.storyline = StorylineSettings(enabled: false,trackID: childPrimary) }
        var parent = TimelineClip(assetID: nil,name: name,start: start,duration: end - start); parent.compoundID = source.id
        var project = original
        for t in project.tracks.indices { project.tracks[t].clips.removeAll { chosen.contains($0.id) } }
        if let primaryIndex {
            project.tracks[primaryIndex].clips.append(parent)
            for t in project.tracks.indices where t != primaryIndex {
                for c in project.tracks[t].clips.indices where project.tracks[t].clips[c].connection.map({ chosen.contains($0.anchor) }) == true {
                    guard !project.tracks[t].locked else { throw RenderError.invalid("Unlock connected tracks before grouping their anchors.") }
                    project.tracks[t].clips[c].connection = ClipConnection(anchor: parent.id,offset: project.tracks[t].clips[c].start - start)
                }
            }
        } else {
            var track = TimelineTrack(name: name,kind: source.kind)
            track.solo = children.contains(where: \.solo); track.clips = [parent]
            project.tracks.insert(track,at: videoIndices.first ?? selectedTracks.first!)
        }
        project.compounds = (project.compounds ?? []) + [source]
        try project.validate(); return project
    }

    public static func breakApart(_ id: UUID,in original: RenderProject) throws -> RenderProject {
        try original.validate()
        guard let location = original.location(id), let parent = original.clip(id), let sourceID = parent.compoundID,
              let source = original.compounds?.first(where: { $0.id == sourceID }) else { throw RenderError.invalid("Select a compound clip first.") }
        let parentTrack = original.tracks[location.track]
        guard !parentTrack.locked else { throw RenderError.invalid("Unlock the compound's track first.") }
        guard parent.speed == 1, parent.properties == ClipProperties(), parent.effects.isEmpty, parent.transition == nil,
              source.settings == original.settings, !parentTrack.hidden, !parentTrack.muted,
              !original.tracks.contains(where: \.solo), !source.tracks.contains(where: \.solo),
              source.tracks.flatMap(\.clips).allSatisfy({ ($0.properties.geometry?.blend ?? .normal) == .normal }) else {
            throw RenderError.invalid("To preserve the result when breaking apart, reset compound transforms/effects/speed, clear solos, and use matching sequence settings with Normal child blending.")
        }
        guard !parentTrack.clips.contains(where: { $0.transition?.rightID == id }) else { throw RenderError.invalid("Remove transitions to this compound before breaking it apart.") }
        let trimStart = original.settings.frameRate.frames(parent.sourceIn), trimEnd = trimStart + parent.duration
        for track in source.tracks {
            for clip in track.clips {
                if let transition = clip.transition {
                    let window = TransitionWindow(left: clip,transition: transition)
                    guard !(trimStart > window.start && trimStart < window.end), !(trimEnd > window.start && trimEnd < window.end) else { throw RenderError.invalid("A compound trim cuts through an internal transition. Adjust the trim before breaking apart.") }
                }
            }
        }
        let visible = source.tracks.flatMap(\.clips).filter { $0.end > trimStart && $0.start < trimEnd }
        let newIDs = Dictionary(uniqueKeysWithValues: visible.map { ($0.id,UUID()) })
        var tracks: [TimelineTrack] = []
        for oldTrack in source.tracks {
            var track = oldTrack; track.id = UUID(); track.clips = []
            for child in oldTrack.clips where newIDs[child.id] != nil {
                let lo = max(trimStart,child.start), hi = min(trimEnd,child.end)
                var copy = child; copy.id = newIDs[child.id]!
                copy.start = parent.start + lo - trimStart; copy.duration = hi - lo
                copy.sourceIn += original.settings.frameRate.seconds(lo - child.start) * copy.speed
                copy.animationOffset += lo - child.start
                if let transition = copy.transition { copy.transition?.rightID = newIDs[transition.rightID] ?? transition.rightID; if newIDs[transition.rightID] == nil { copy.transition = nil } }
                copy.connection = nil
                track.clips.append(copy)
            }
            tracks.append(track)
        }
        var project = original
        project.tracks[location.track].clips.remove(at: location.clip)
        if project.storyline?.trackID == parentTrack.id {
            guard let childPrimary = source.storyline?.trackID, let index = source.tracks.firstIndex(where: { $0.id == childPrimary }) else { throw RenderError.invalid("This compound has no primary storyline to restore.") }
            guard !tracks[index].locked else { throw RenderError.invalid("Unlock the internal primary track before restoring it to the parent storyline.") }
            var primary = tracks.remove(at: index).clips.sorted { $0.start < $1.start }
            if project.storyline?.enabled == true {
                var cursor = parent.start, filled: [TimelineClip] = []
                for clip in primary {
                    if cursor < clip.start { var gap = TimelineClip(assetID: nil,name: "Gap",start: cursor,duration: clip.start - cursor); gap.isGap = true; filled.append(gap) }
                    filled.append(clip); cursor = clip.end
                }
                if cursor < parent.end { var gap = TimelineClip(assetID: nil,name: "Gap",start: cursor,duration: parent.end - cursor); gap.isGap = true; filled.append(gap) }
                primary = filled
            }
            project.tracks[location.track].clips.append(contentsOf: primary)
            for t in project.tracks.indices {
                for c in project.tracks[t].clips.indices where project.tracks[t].clips[c].connection?.anchor == id {
                    guard !project.tracks[t].locked else { throw RenderError.invalid("Unlock connected tracks before restoring their anchors.") }
                    let start = project.tracks[t].clips[c].start
                    if let anchor = primary.last(where: { $0.start <= start }) ?? primary.first { project.tracks[t].clips[c].connection = ClipConnection(anchor: anchor.id,offset: start - anchor.start) }
                    else { project.tracks[t].clips[c].connection = nil }
                }
            }
        }
        project.tracks.insert(contentsOf: tracks,at: location.track)
        try project.validate(); return project
    }
}
