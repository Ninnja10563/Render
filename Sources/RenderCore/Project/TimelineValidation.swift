import Foundation

extension ProjectSettings {
    public func validate() throws {
        guard width >= 16, width <= 8192, height >= 16, height <= 8192,
              width % 2 == 0, height % 2 == 0,
              frameRate.numerator > 0, frameRate.denominator > 0,
              (1...120).contains(frameRate.value) else { throw RenderError.invalid("Invalid project dimensions or frame rate.") }
    }
}

extension RenderProject {
    func validateTimeline(mediaByID: [UUID: MediaAsset],multicams: [UUID: MulticamSource],sources: [UUID: CompoundSource]) throws {
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
                if let compoundID = clip.compoundID {
                    guard clip.assetID == nil, clip.title == nil, clip.isGap != true, clip.multicam == nil,
                          let source = sources[compoundID], track.kind == source.kind else { throw RenderError.invalid("Invalid compound clip reference or track type.") }
                    guard clip.sourceIn + settings.frameRate.seconds(clip.duration) * clip.speed <= source.seconds + 0.001 else { throw RenderError.invalid("Edit extends past the compound source. Extend its contents before trimming further.") }
                } else if clip.isGap == true {
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
                if let effects = p.audioEffects, !effects.isEmpty {
                    guard effects.count <= 16, Set(effects.map(\.id)).count == effects.count else { throw RenderError.invalid("An audio clip supports up to 16 distinct processors.") }
                    guard clip.compoundID == nil, let assetID = clip.assetID, let media = mediaByID[assetID], media.audioChannels > 0, media.audioChannels <= 8 else { throw RenderError.invalid("Audio processors require a source clip with one to eight channels. Open a compound to process its audio sources.") }
                    for effect in effects { try effect.validate() }
                }
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
