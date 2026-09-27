import Foundation
import AVFoundation
import CoreImage
import RenderCore

public struct PreparedComposition {
    public let composition: AVMutableComposition
    public let videoComposition: AVMutableVideoComposition
    public let audioMix: AVMutableAudioMix
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
    public func build(_ project: RenderProject) async throws -> PreparedComposition {
        try project.validate()
        guard project.duration > 0 else { throw RenderError.invalid("Add a clip to the timeline first.") }
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
        var parameters: [AVMutableAudioMixInputParameters] = []
        let anySolo = project.tracks.contains { $0.solo }
        for track in project.tracks {
            for clip in track.clips {
                try Task.checkCancellation()
                guard let media = project.assets.first(where: { $0.id == clip.assetID }) else { continue }
                guard FileManager.default.fileExists(atPath: media.url.path) else { throw RenderError.missingMedia(media.name) }
                let start = time(rate.seconds(clip.start))
                let targetDuration = time(rate.seconds(clip.duration))
                let range = CMTimeRange(start: time(clip.sourceIn), duration: time(rate.seconds(clip.duration) * clip.speed))
                if media.kind == .image {
                    if !track.hidden {
                        guard let image = CIImage(contentsOf: media.url, options: [.applyOrientationProperty: true]) else { throw RenderError.invalid("Could not decode \(media.name).") }
                        layers.append(RenderLayer(trackID: clock.trackID, clip: clip, preferredTransform: .identity, still: image))
                    }
                    continue
                }
                let asset = AVURLAsset(url: media.url)
                if track.kind == .video && !track.hidden, let source = try await asset.loadTracks(withMediaType: .video).first {
                    guard let target = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw RenderError.invalid("Too many video tracks.") }
                    try target.insertTimeRange(range, of: source, at: start)
                    target.scaleTimeRange(CMTimeRange(start: start, duration: range.duration), toDuration: targetDuration)
                    layers.append(RenderLayer(trackID: target.trackID, clip: clip, preferredTransform: try await source.load(.preferredTransform), still: nil))
                }
                if !track.muted && !clip.properties.muted && (!anySolo || track.solo), let source = try await asset.loadTracks(withMediaType: .audio).first {
                    guard let target = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw RenderError.invalid("Too many audio tracks.") }
                    // Some camera files have audio shorter than their video stream.
                    let available = try await source.load(.timeRange)
                    let safeEnd = min(CMTimeGetSeconds(available.end), clip.sourceIn + range.duration.seconds)
                    let safeStart = max(clip.sourceIn, available.start.seconds)
                    if safeEnd <= safeStart { continue }
                    let audioRange = CMTimeRange(start: time(safeStart), duration: time(safeEnd - safeStart))
                    let audioStart = start + time((safeStart - clip.sourceIn) / clip.speed)
                    try target.insertTimeRange(audioRange, of: source, at: audioStart)
                    target.scaleTimeRange(CMTimeRange(start: audioStart, duration: audioRange.duration), toDuration: time(audioRange.duration.seconds / clip.speed))
                    let mix = AVMutableAudioMixInputParameters(track: target)
                    mix.audioTimePitchAlgorithm = .spectral
                    let curve = clip.properties.animations["volume"]
                    if curve?.keys.isEmpty == false {
                        // Sample automation at frame boundaries, preserving hold/ease interpolation.
                        for f in 0..<clip.duration {
                            let a = Float(clip.properties.value("volume", at: Double(f + clip.animationOffset)))
                            let b = Float(clip.properties.value("volume", at: Double(f + 1 + clip.animationOffset)))
                            mix.setVolumeRamp(fromStartVolume: a, toEndVolume: b, timeRange: CMTimeRange(start: start + time(rate.seconds(f)), duration: time(rate.seconds(1))))
                        }
                    } else { mix.setVolume(Float(clip.properties.volume), at: audioStart) }
                    parameters.append(mix)
                }
            }
        }
        let video = AVMutableVideoComposition()
        video.customVideoCompositorClass = VideoCompositor.self
        video.renderSize = CGSize(width: project.settings.width, height: project.settings.height)
        video.frameDuration = CMTime(value: Int64(rate.denominator), timescale: rate.numerator)
        let boundaries = Set([Int64(0), project.duration] + layers.flatMap { [$0.clip.start, $0.clip.end] }).sorted()
        video.instructions = zip(boundaries,boundaries.dropFirst()).map { a,b in
            RenderInstruction(range: CMTimeRange(start: time(rate.seconds(a)), duration: time(rate.seconds(b-a))), layers: layers.filter { $0.clip.start <= a && $0.clip.end > a }, clock: clock.trackID, frameRate: rate)
        }
        let audio = AVMutableAudioMix(); audio.inputParameters = parameters
        return PreparedComposition(composition: composition, videoComposition: video, audioMix: audio)
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
