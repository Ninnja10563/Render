import Foundation
import AVFoundation
import CoreImage
import RenderCore

public struct PreparedComposition {
    public let composition: AVMutableComposition
    public let videoComposition: AVMutableVideoComposition
    public let audioMix: AVMutableAudioMix
    public let originalFallbacks: [String]
    public var audioMeters: [AudioMeterSource] = []
    public var audioProcessing: [AudioMeterSource] = []
    public func checkAudioProcessing() throws {
        if let input = audioProcessing.first(where: \.processingFailed) { throw RenderError.invalid("Unsupported audio processing format for \(input.name).") }
    }
    public func playerItem() -> AVPlayerItem {
        let item = AVPlayerItem(asset: composition)
        item.videoComposition = videoComposition; item.audioMix = audioMix
        item.audioTimePitchAlgorithm = .spectral
        return item
    }
}

public actor CompositionBuilder {
    public init() {}
    private func time(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 600_000) }
    public func build(_ project: RenderProject,mode: PlaybackMediaMode = .original,outputSize: CGSize? = nil,metering: Bool = false) async throws -> PreparedComposition {
        try project.validate()
        guard project.duration > 0 else { throw RenderError.invalid("Add a clip to the timeline first.") }
        if project.tracks.flatMap(\.clips).contains(where: { $0.compoundID != nil }) {
            return try await CompoundCompositionBuilder().build(project,mode: mode,outputSize: outputSize,metering: metering)
        }
        let rate = project.settings.frameRate
        let composition = AVMutableComposition()
        let duration = time(rate.seconds(project.duration))
        // A tiny clock track drives black gaps, still images and audio-only sequences.
        let clockURL = try await ClockMovie.make(duration: duration)
        let clockAsset = AVURLAsset(url: clockURL)
        guard let clockSource = try await clockAsset.loadTracks(withMediaType: .video).first,
              let clock = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw RenderError.invalid("Cannot create the timeline clock.") }
        try clock.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: clockSource, at: .zero)
        var layers: [RenderLayer] = []
        var fallbacks: Set<String> = []
        var parameters: [AVMutableAudioMixInputParameters] = []
        let processing = AudioInputProcessing(metering: metering)
        let anySolo = project.tracks.contains { $0.solo }
        let mediaByID = Dictionary(uniqueKeysWithValues: project.assets.map { ($0.id,$0) })
        var sourceCache: [URL: SourceTracks] = [:]
        var stillCache: [URL: CIImage] = [:]
        for track in project.tracks {
            var videoSlots: [(track: AVMutableCompositionTrack,end: CMTime)] = []
            var audioSlots: [(track: AVMutableCompositionTrack,mix: AVMutableAudioMixInputParameters,end: CMTime)] = []
            let windows = Dictionary(uniqueKeysWithValues: track.clips.compactMap { clip -> (UUID,TransitionWindow)? in
                guard let transition = clip.transition else { return nil }
                return (transition.rightID,TransitionWindow(left: clip,transition: transition))
            })
            // Insert in time order: scaling a source segment must never displace a later edit.
            for clip in track.clips.sorted(by: { $0.start < $1.start }) {
                try Task.checkCancellation()
                let incoming = windows[clip.id]
                let outgoing = clip.transition.map { TransitionWindow(left: clip,transition: $0) }
                let renderStart = incoming?.start ?? clip.start, renderEnd = outgoing?.end ?? clip.end
                let preroll = clip.start - renderStart
                if clip.isGap == true {
                    if !track.hidden { layers.append(RenderLayer(trackID: clock.trackID,clip: clip,preferredTransform: .identity,still: CIImage(color: .black).cropped(to: CGRect(x: 0,y: 0,width: project.settings.width,height: project.settings.height)),incoming: incoming,outgoing: outgoing)) }
                    continue
                }
                if let title = clip.title {
                    if !track.hidden { layers.append(RenderLayer(trackID: clock.trackID,clip: clip,preferredTransform: .identity,still: nil,title: title,incoming: incoming,outgoing: outgoing)) }
                    continue
                }
                guard let assetID = clip.assetID, let media = mediaByID[assetID] else { continue }
                var selectedURL = MediaResolver.url(for: media,mode: mode)
                if mode != .original && media.kind == .video && selectedURL == media.url { fallbacks.insert(media.name) }
                guard FileManager.default.fileExists(atPath: selectedURL.path) else { throw RenderError.missingMedia(media.name) }
                let start = time(rate.seconds(renderStart))
                let targetDuration = time(rate.seconds(renderEnd - renderStart))
                let range = CMTimeRange(start: time(clip.sourceIn - rate.seconds(preroll) * clip.speed), duration: time(rate.seconds(renderEnd - renderStart) * clip.speed))
                if media.kind == .image {
                    if !track.hidden {
                        guard let image = stillCache[media.url] ?? CIImage(contentsOf: media.url, options: [.applyOrientationProperty: true]) else { throw RenderError.invalid("Could not decode \(media.name).") }
                        stillCache[media.url] = image
                        layers.append(RenderLayer(trackID: clock.trackID, clip: clip, preferredTransform: .identity, still: image,incoming: incoming,outgoing: outgoing))
                    }
                    continue
                }
                let sources: SourceTracks
                do {
                    let loaded: SourceTracks
                    if let cached = sourceCache[selectedURL] { loaded = cached }
                    else { loaded = try await SourceTracks.load(selectedURL) }
                    if selectedURL != media.url {
                        guard loaded.video != nil, let available = loaded.videoRange,
                              available.start.seconds <= range.start.seconds + 0.001,
                              available.end.seconds + 0.001 >= range.end.seconds else { throw RenderError.invalid("Generated media does not cover this edit.") }
                    }
                    sources = loaded; sourceCache[selectedURL] = sources
                } catch {
                    guard selectedURL != media.url else { throw error }
                    selectedURL = media.url; fallbacks.insert(media.name)
                    if let cached = sourceCache[selectedURL] { sources = cached }
                    else { sources = try await SourceTracks.load(selectedURL); sourceCache[selectedURL] = sources }
                }
                // Keep audio at source quality when originals are online, even in proxy video mode.
                let audioSources: SourceTracks
                if selectedURL != media.url && FileManager.default.fileExists(atPath: media.url.path) {
                    if let cached = sourceCache[media.url] { audioSources = cached }
                    else { audioSources = try await SourceTracks.load(media.url); sourceCache[media.url] = audioSources }
                } else { audioSources = sources }
                if track.kind == .video && !track.hidden, let source = sources.video {
                    let slot: Int
                    if let available = videoSlots.firstIndex(where: { $0.end <= start }) { slot = available }
                    else {
                        guard let target = composition.addMutableTrack(withMediaType: .video,preferredTrackID: kCMPersistentTrackID_Invalid) else { throw RenderError.invalid("Too many video tracks.") }
                        videoSlots.append((target,.zero)); slot = videoSlots.count - 1
                    }
                    let target = videoSlots[slot].track
                    videoSlots[slot].end = start + targetDuration
                    try target.insertTimeRange(range, of: source, at: start)
                    target.scaleTimeRange(CMTimeRange(start: start, duration: range.duration), toDuration: targetDuration)
                    layers.append(RenderLayer(trackID: target.trackID, clip: clip, preferredTransform: sources.transform, still: nil,incoming: incoming,outgoing: outgoing))
                }
                if !track.muted && !clip.properties.muted && (!anySolo || track.solo), let source = audioSources.audio, let available = audioSources.audioRange {
                    // Some camera files have audio shorter than their video stream.
                    let safeEnd = min(CMTimeGetSeconds(available.end), range.end.seconds)
                    let safeStart = max(range.start.seconds, available.start.seconds)
                    if safeEnd <= safeStart { continue }
                    let audioRange = CMTimeRange(start: time(safeStart), duration: time(safeEnd - safeStart))
                    let audioStart = start + time((safeStart - range.start.seconds) / clip.speed)
                    let slot: Int
                    if let available = audioSlots.firstIndex(where: { $0.end <= start }) { slot = available }
                    else {
                        guard let target = composition.addMutableTrack(withMediaType: .audio,preferredTrackID: kCMPersistentTrackID_Invalid) else { throw RenderError.invalid("Too many audio tracks.") }
                        let mix = AVMutableAudioMixInputParameters(track: target); mix.audioTimePitchAlgorithm = .spectral
                        mix.setVolume(0,at: .zero)
                        audioSlots.append((target,mix,.zero)); slot = audioSlots.count - 1
                    }
                    let target = audioSlots[slot].track, mix = audioSlots[slot].mix
                    audioSlots[slot].end = start + targetDuration
                    try target.insertTimeRange(audioRange, of: source, at: audioStart)
                    target.scaleTimeRange(CMTimeRange(start: audioStart, duration: audioRange.duration), toDuration: time(audioRange.duration.seconds / clip.speed))
                    let input = try processing.attach(clip: clip,name: "\(track.name) · \(clip.name)",target: target,mix: mix,start: audioStart.seconds,end: (audioStart + time(audioRange.duration.seconds / clip.speed)).seconds)
                    let curve = clip.properties.animations["volume"] ?? AnimationCurve()
                    let base = AudioAutomation.ramps(curve: curve,offset: clip.animationOffset - preroll,duration: renderEnd - renderStart,fallback: clip.properties.volume)
                    let faded = AudioAutomation.applying(clip.properties.audioFades,to: base,offset: clip.animationOffset - preroll)
                    let ramps = AudioAutomation.applyingFades(to: faded,duration: renderEnd - renderStart,fadeIn: incoming?.duration ?? 0,fadeOut: outgoing?.duration ?? 0)
                    for ramp in ramps {
                        try input?.appendVolumeRamp(from: Float(ramp.from),to: Float(ramp.to),start: (start + time(rate.seconds(ramp.start))).seconds,end: (start + time(rate.seconds(ramp.end))).seconds)
                        mix.setVolumeRamp(fromStartVolume: Float(ramp.from),toEndVolume: Float(ramp.to),
                                          timeRange: CMTimeRange(start: start + time(rate.seconds(ramp.start)),duration: time(rate.seconds(ramp.end - ramp.start))))
                    }
                }
            }
            parameters.append(contentsOf: audioSlots.map(\.mix))
        }
        let video = AVMutableVideoComposition()
        video.customVideoCompositorClass = VideoCompositor.self
        video.renderSize = outputSize ?? CGSize(width: project.settings.width, height: project.settings.height)
        video.frameDuration = CMTime(value: Int64(rate.denominator), timescale: rate.numerator)
        // Sweep clip boundaries instead of scanning every clip for every instruction.
        var entering: [Int64: [Int]] = [:]
        var leaving: [Int64: [Int]] = [:]
        for (index,layer) in layers.enumerated() {
            entering[layer.start,default: []].append(index)
            leaving[layer.end,default: []].append(index)
        }
        let boundaries = Set([Int64(0),project.duration] + Array(entering.keys) + Array(leaving.keys)).sorted()
        var active: Set<Int> = []
        var instructions: [RenderInstruction] = []
        for (a,b) in zip(boundaries,boundaries.dropFirst()) {
            for index in leaving[a] ?? [] { active.remove(index) }
            for index in entering[a] ?? [] { active.insert(index) }
            instructions.append(RenderInstruction(range: CMTimeRange(start: time(rate.seconds(a)),duration: time(rate.seconds(b-a))),layers: active.sorted().map { layers[$0] },clock: clock.trackID,frameRate: rate,designSize: CGSize(width: project.settings.width,height: project.settings.height)))
        }
        video.instructions = instructions
        let audio = AVMutableAudioMix(); audio.inputParameters = parameters
        // Keep source owners alive through all insertions even under Release ARC optimization.
        withExtendedLifetime(sourceCache) {}
        return PreparedComposition(composition: composition, videoComposition: video, audioMix: audio, originalFallbacks: fallbacks.sorted(),audioMeters: processing.meters,audioProcessing: processing.inputs)
    }
}

struct SourceTracks {
    // AVAssetTrack.asset is weak; keep the owner alive while its tracks are inserted.
    let asset: AVURLAsset
    let video: AVAssetTrack?
    let audio: AVAssetTrack?
    let transform: CGAffineTransform
    let audioRange: CMTimeRange?
    let videoRange: CMTimeRange?
    static func load(_ url: URL) async throws -> SourceTracks {
        let asset = AVURLAsset(url: url)
        let video = try await asset.loadTracks(withMediaType: .video).first
        let audio = try await asset.loadTracks(withMediaType: .audio).first
        let transform = try await video?.load(.preferredTransform) ?? .identity
        let audioRange = try await audio?.load(.timeRange)
        let videoRange = try await video?.load(.timeRange)
        return SourceTracks(asset: asset,video: video,audio: audio,transform: transform,audioRange: audioRange,videoRange: videoRange)
    }
}

private enum ClockMovie {
    static func make(duration: CMTime) async throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Render-Clock", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(duration.value)-\(duration.timescale).mov")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let temporary = folder.appendingPathComponent(UUID().uuidString + ".mov")
        let writer = try AVAssetWriter(outputURL: temporary, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 16, AVVideoHeightKey: 16])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 16, kCVPixelBufferHeightKey as String: 16])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? RenderError.invalid("Cannot start timeline clock.") }
        writer.startSession(atSourceTime: .zero)
        guard let pool = adaptor.pixelBufferPool else { throw RenderError.invalid("Cannot allocate clock frame.") }
        var pixel: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixel)
        guard let pixel else { throw RenderError.invalid("Cannot allocate clock frame.") }
        CVPixelBufferLockBaseAddress(pixel, [])
        if let base = CVPixelBufferGetBaseAddress(pixel) { memset(base, 0, CVPixelBufferGetDataSize(pixel)) }
        CVPixelBufferUnlockBaseAddress(pixel, [])
        do {
            let last = max(.zero, duration - CMTime(value: 1, timescale: 600_000))
            for timestamp in last > .zero ? [CMTime.zero,last] : [.zero] {
                while !input.isReadyForMoreMediaData {
                    try Task.checkCancellation()
                    if writer.status == .failed { throw writer.error ?? RenderError.invalid("Clock encoding failed.") }
                    try await Task.sleep(nanoseconds: 1_000_000)
                }
                guard adaptor.append(pixel, withPresentationTime: timestamp) else { throw writer.error ?? RenderError.invalid("Clock frame encoding failed.") }
            }
            writer.endSession(atSourceTime: duration); input.markAsFinished()
            await writer.finishWriting()
            guard writer.status == .completed else { throw writer.error ?? RenderError.invalid("Cannot finish timeline clock.") }
            if FileManager.default.fileExists(atPath: url.path) { try? FileManager.default.removeItem(at: temporary) }
            else { try FileManager.default.moveItem(at: temporary, to: url) }
            return url
        } catch {
            writer.cancelWriting(); try? FileManager.default.removeItem(at: temporary); throw error
        }
    }
}
