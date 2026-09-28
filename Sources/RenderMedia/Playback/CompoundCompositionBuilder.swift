import AVFoundation
import CoreImage
import RenderCore

/// Compiles nested timeline instances without baking intermediate movies. Each instance has
/// distinct render IDs, while source asset owners and nonoverlapping composition slots are shared.
actor CompoundCompositionBuilder {
    func build(_ project: RenderProject,mode: PlaybackMediaMode,outputSize: CGSize?,metering: Bool) async throws -> PreparedComposition {
        var clockProject = project
        var clockTrack = TimelineTrack(name: "Clock",kind: .video)
        var gap = TimelineClip(assetID: nil,name: "Clock",start: 0,duration: project.duration); gap.isGap = true
        clockTrack.clips = [gap]; clockProject.tracks = [clockTrack]; clockProject.storyline = nil; clockProject.markers = []
        let base = try await CompositionBuilder().build(clockProject,outputSize: outputSize)
        guard let clock = base.composition.tracks.first(where: { $0.mediaType == .video }) else { throw RenderError.invalid("Timeline clock is missing.") }
        let planner = CompoundPlanner(project: project,mode: mode,composition: base.composition,clock: clock.trackID,metering: metering)
        try await planner.compile()
        base.videoComposition.instructions = planner.instructions()
        base.audioMix.inputParameters = planner.audioSlots.map(\.mix)
        withExtendedLifetime(planner.sources) {}
        return PreparedComposition(composition: base.composition,videoComposition: base.videoComposition,audioMix: base.audioMix,originalFallbacks: planner.fallbacks.sorted(),audioMeters: planner.processing.meters,audioProcessing: planner.processing.inputs)
    }
}

private final class CompoundPlanner {
    let project: RenderProject
    let mode: PlaybackMediaMode
    let composition: AVMutableComposition
    let clock: CMPersistentTrackID
    let metering: Bool
    let processing: AudioInputProcessing
    let media: [UUID: MediaAsset]
    let compounds: [UUID: CompoundSource]
    var sources: [URL: SourceTracks] = [:]
    var stills: [URL: CIImage] = [:]
    var fallbacks: Set<String> = []
    var videoSlots: [(track: AVMutableCompositionTrack,end: CMTime)] = []
    var audioSlots: [(track: AVMutableCompositionTrack,mix: AVMutableAudioMixInputParameters,end: CMTime)] = []
    struct Entry { var node: RenderNode; var parent: UUID; var order: Int; var start: Int64; var end: Int64 }
    let root = UUID()
    var entries: [UUID: Entry] = [:]
    init(project: RenderProject,mode: PlaybackMediaMode,composition: AVMutableComposition,clock: CMPersistentTrackID,metering: Bool) {
        self.project = project; self.mode = mode; self.composition = composition; self.clock = clock; self.metering = metering; processing = AudioInputProcessing(metering: metering)
        media = Dictionary(uniqueKeysWithValues: project.assets.map { ($0.id,$0) })
        compounds = Dictionary(uniqueKeysWithValues: (project.compounds ?? []).map { ($0.id,$0) })
    }
    func time(_ seconds: Double) -> CMTime { CompoundAudioMix.time(seconds) }
    func compile() async throws {
        try await visit(project.tracks,settings: project.settings,mapping: TimelineTimeMapping(),window: RenderTimeWindow(start: 0,end: project.settings.frameRate.seconds(project.duration)),parent: root,visible: true,audible: true,envelopes: [])
    }
    func visit(_ tracks: [TimelineTrack],settings: ProjectSettings,mapping: TimelineTimeMapping,window: RenderTimeWindow,parent: UUID,visible: Bool,audible: Bool,envelopes: [CompoundAudioEnvelope]) async throws {
        let rate = settings.frameRate, anySolo = tracks.contains { $0.solo }
        let ids = Dictionary(uniqueKeysWithValues: tracks.flatMap(\.clips).map { ($0.id,UUID()) })
        var order = 0
        for track in tracks {
            var clips = track.clips.sorted { $0.start < $1.start }
            for i in clips.indices {
                clips[i].id = ids[clips[i].id]!
                if let right = clips[i].transition?.rightID { clips[i].transition?.rightID = ids[right]! }
            }
            let incoming = Dictionary(uniqueKeysWithValues: clips.compactMap { clip -> (UUID,TransitionWindow)? in
                guard let t = clip.transition else { return nil }; return (t.rightID,TransitionWindow(left: clip,transition: t))
            })
            for clip in clips {
                try Task.checkCancellation()
                let inWindow = incoming[clip.id], outWindow = clip.transition.map { TransitionWindow(left: clip,transition: $0) }
                guard let span = window.intersecting(start: mapping.global(rate.seconds(inWindow?.start ?? clip.start)),end: mapping.global(rate.seconds(outWindow?.end ?? clip.end))) else { continue }
                let show = visible && !track.hidden && track.kind == .video
                let hear = audible && !track.muted && !clip.properties.muted && (!anySolo || track.solo)
                let envelope = CompoundAudioEnvelope(clip: clip,rate: rate,mapping: mapping,incoming: inWindow,outgoing: outWindow)
                let gains = envelope.isIdentity ? envelopes : envelopes + [envelope]
                let ordinal = order; order += 1
                if let id = clip.compoundID, let source = compounds[id] {
                    if show { add(.group(RenderGroup(clip: clip,children: [],settings: source.settings,incoming: inWindow,outgoing: outWindow)),parent: parent,order: ordinal,window: span) }
                    try await visit(source.tracks,settings: source.settings,mapping: mapping.entering(clip,rate: rate),window: span,parent: clip.id,visible: show,audible: hear,envelopes: gains)
                    continue
                }
                if clip.isGap == true || clip.title != nil {
                    if show {
                        let still = clip.isGap == true ? CIImage(color: .black).cropped(to: CGRect(x: 0,y: 0,width: settings.width,height: settings.height)) : nil
                        add(.layer(RenderLayer(trackID: clock,clip: clip,preferredTransform: .identity,still: still,title: clip.title,incoming: inWindow,outgoing: outWindow)),parent: parent,order: ordinal,window: span)
                    }
                    continue
                }
                guard let id = clip.assetID, let asset = media[id] else { continue }
                if asset.kind == .image {
                    if show {
                        guard let image = stills[asset.url] ?? CIImage(contentsOf: asset.url,options: [.applyOrientationProperty: true]) else { throw RenderError.invalid("Could not decode \(asset.name).") }
                        stills[asset.url] = image
                        add(.layer(RenderLayer(trackID: clock,clip: clip,preferredTransform: .identity,still: image,incoming: inWindow,outgoing: outWindow)),parent: parent,order: ordinal,window: span)
                    }
                    continue
                }
                if !show && !hear { continue }
                let speed = clip.speed / mapping.scale
                let sourceStart = max(0,clip.sourceIn + (mapping.local(span.start) - rate.seconds(clip.start)) * clip.speed)
                let range = CMTimeRange(start: time(sourceStart),duration: time((span.end - span.start) * speed))
                var url = MediaResolver.url(for: asset,mode: mode)
                if mode != .original && asset.kind == .video && url == asset.url { fallbacks.insert(asset.name) }
                let source: SourceTracks
                do {
                    let loaded = try await load(url)
                    if url != asset.url {
                        guard loaded.video != nil, let available = loaded.videoRange, available.start.seconds <= range.start.seconds + 0.001, available.end.seconds + 0.001 >= range.end.seconds else { throw RenderError.invalid("Generated media does not cover this edit.") }
                    }
                    source = loaded
                } catch {
                    guard url != asset.url else { throw error }
                    url = asset.url; fallbacks.insert(asset.name); source = try await load(url)
                }
                let start = time(span.start), duration = time(span.end) - start
                if show, let video = source.video {
                    let slot: Int
                    if let free = videoSlots.firstIndex(where: { $0.end <= start }) { slot = free }
                    else {
                        guard let target = composition.addMutableTrack(withMediaType: .video,preferredTrackID: kCMPersistentTrackID_Invalid) else { throw RenderError.invalid("Too many video tracks.") }
                        videoSlots.append((target,.zero)); slot = videoSlots.count - 1
                    }
                    let target = videoSlots[slot].track; videoSlots[slot].end = time(span.end)
                    try target.insertTimeRange(range,of: video,at: start)
                    target.scaleTimeRange(CMTimeRange(start: start,duration: range.duration),toDuration: duration)
                    add(.layer(RenderLayer(trackID: target.trackID,clip: clip,preferredTransform: source.transform,still: nil,incoming: inWindow,outgoing: outWindow)),parent: parent,order: ordinal,window: span)
                }
                if hear {
                    let audioSource = url != asset.url && FileManager.default.fileExists(atPath: asset.url.path) ? try await load(asset.url) : source
                    if let audio = audioSource.audio, let available = audioSource.audioRange {
                        let lo = max(range.start.seconds,available.start.seconds), hi = min(range.end.seconds,available.end.seconds)
                        if hi <= lo { continue }
                        let audioStart = start + time((lo - range.start.seconds) / speed)
                        let audioRange = CMTimeRange(start: time(lo),duration: time(hi - lo))
                        let slot: Int
                        if let free = audioSlots.firstIndex(where: { $0.end <= start }) { slot = free }
                        else {
                            guard let target = composition.addMutableTrack(withMediaType: .audio,preferredTrackID: kCMPersistentTrackID_Invalid) else { throw RenderError.invalid("Too many audio tracks.") }
                            let mix = AVMutableAudioMixInputParameters(track: target); mix.audioTimePitchAlgorithm = .spectral
                            mix.setVolume(0,at: .zero)
                            audioSlots.append((target,mix,.zero)); slot = audioSlots.count - 1
                        }
                        let target = audioSlots[slot].track; audioSlots[slot].end = time(span.end)
                        try target.insertTimeRange(audioRange,of: audio,at: audioStart)
                        target.scaleTimeRange(CMTimeRange(start: audioStart,duration: audioRange.duration),toDuration: time((hi - lo) / speed))
                        let input = try processing.attach(clip: clip,name: "\(track.name) · \(clip.name)",target: target,mix: audioSlots[slot].mix,start: audioStart.seconds,end: min(time(span.end).seconds,(audioStart + time((hi - lo) / speed)).seconds))
                        try CompoundAudioMix.apply(gains,window: span,to: audioSlots[slot].mix,meter: input)
                    }
                }
            }
        }
    }
    func load(_ url: URL) async throws -> SourceTracks {
        if let cached = sources[url] { return cached }
        guard FileManager.default.fileExists(atPath: url.path) else { throw RenderError.missingMedia(url.lastPathComponent) }
        let value = try await SourceTracks.load(url); sources[url] = value; return value
    }
    func add(_ node: RenderNode,parent: UUID,order: Int,window: RenderTimeWindow) {
        entries[node.clip.id] = Entry(node: node,parent: parent,order: order,start: time(window.start).value,end: time(window.end).value)
    }
    func instructions() -> [RenderInstruction] {
        var entering: [Int64: [UUID]] = [:], leaving: [Int64: [UUID]] = [:]
        for (id,entry) in entries where entry.end > entry.start {
            entering[entry.start,default: []].append(id); leaving[entry.end,default: []].append(id)
        }
        let end = time(project.settings.frameRate.seconds(project.duration)).value
        let boundaries = Set([Int64(0),end] + Array(entering.keys) + Array(leaving.keys)).sorted()
        var active: [UUID: Set<UUID>] = [:]
        func nodes(_ parent: UUID) -> [RenderNode] {
            (active[parent] ?? []).compactMap { entries[$0] }.sorted { $0.order < $1.order }.map { entry in
                switch entry.node {
                case .layer: return entry.node
                case .group(var group): group.children = nodes(group.clip.id); return .group(group)
                }
            }
        }
        var result: [RenderInstruction] = []
        for (a,b) in zip(boundaries,boundaries.dropFirst()) {
            for id in leaving[a] ?? [] { if let entry = entries[id] { active[entry.parent]?.remove(id) } }
            for id in entering[a] ?? [] { if let entry = entries[id] { active[entry.parent,default: []].insert(id) } }
            result.append(RenderInstruction(range: CMTimeRange(start: CMTime(value: a,timescale: CompoundAudioMix.timescale),duration: CMTime(value: b - a,timescale: CompoundAudioMix.timescale)),nodes: nodes(root),clock: clock,frameRate: project.settings.frameRate,designSize: CGSize(width: project.settings.width,height: project.settings.height)))
        }
        return result
    }
}
