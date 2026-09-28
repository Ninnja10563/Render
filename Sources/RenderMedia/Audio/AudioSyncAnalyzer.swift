import AVFoundation
import RenderCore

public actor AudioSyncAnalyzer {
    public init() {}
    /// 100 Hz RMS envelopes, limited to the first two minutes of each selected edit.
    public func analyze(reference: MediaAsset,referenceClip: TimelineClip,target: MediaAsset,targetClip: TimelineClip,rate: FrameRate) async throws -> AudioSyncMatch {
        guard referenceClip.speed == 1, targetClip.speed == 1 else { throw RenderError.invalid("Audio synchronization currently requires 100% clip speed.") }
        let a = try await envelope(url: reference.url,start: referenceClip.sourceIn,duration: min(120,rate.seconds(referenceClip.duration)))
        let b = try await envelope(url: target.url,start: targetClip.sourceIn,duration: min(120,rate.seconds(targetClip.duration)))
        return try AudioSynchronization.match(reference: a,target: b,maximumOffset: 3000,minimumOverlap: max(100,min(a.count,b.count) / 3))
    }
    public func envelope(url: URL,start: Double,duration: Double) async throws -> [Float] {
        guard start.isFinite, start >= 0, duration.isFinite, (1...120).contains(duration) else { throw RenderError.invalid("Select clips with at least one second of audio.") }
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw RenderError.invalid("This source has no audio track.") }
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: CMTime(seconds: start,preferredTimescale: 48000),duration: CMTime(seconds: duration,preferredTimescale: 48000))
        let output = AVAssetReaderTrackOutput(track: track,outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM,AVLinearPCMIsFloatKey: true,AVLinearPCMBitDepthKey: 32,AVLinearPCMIsNonInterleaved: false])
        guard reader.canAdd(output) else { throw RenderError.invalid("Cannot decode audio for synchronization.") }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? RenderError.invalid("Cannot start audio analysis.") }
        defer { if reader.status == .reading { reader.cancelReading() } }
        let bins = Int((duration * 100).rounded(.down))
        var sums = [Double](repeating: 0,count: bins), counts = [Int](repeating: 0,count: bins)
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let block = CMSampleBufferGetDataBuffer(sample), let format = CMSampleBufferGetFormatDescription(sample),
                  let description = CMAudioFormatDescriptionGetStreamBasicDescription(format) else { throw RenderError.invalid("Invalid decoded audio format.") }
            let channels = Int(description.pointee.mChannelsPerFrame), sampleRate = description.pointee.mSampleRate
            guard channels > 0, sampleRate > 0 else { throw RenderError.invalid("Invalid audio channel configuration.") }
            let count = CMBlockBufferGetDataLength(block) / MemoryLayout<Float>.size
            var values = [Float](repeating: 0,count: count)
            let status = values.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block,atOffset: 0,dataLength: $0.count,destination: $0.baseAddress!) }
            guard status == kCMBlockBufferNoErr else { throw RenderError.invalid("Cannot read decoded audio samples.") }
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            guard timestamp.isFinite else { throw RenderError.invalid("Invalid audio timestamp.") }
            for frame in 0..<(count / channels) {
                let relative = timestamp - start + Double(frame) / sampleRate
                guard relative >= 0, relative < duration else { continue }
                let bin = min(bins - 1,Int(relative * 100))
                for channel in 0..<channels {
                    let value = Double(values[frame * channels + channel])
                    if value.isFinite { sums[bin] += value * value; counts[bin] += 1 }
                }
            }
            await Task.yield()
        }
        if reader.status == .failed { throw reader.error ?? RenderError.invalid("Audio analysis failed.") }
        return zip(sums,counts).map { Float(sqrt($0 / Double(max(1,$1)))) }
    }
}
