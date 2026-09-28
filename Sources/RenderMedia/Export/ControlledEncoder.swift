import AVFoundation
import VideoToolbox
import RenderCore

/// Owns synchronous sample-buffer I/O away from the main actor, with encoder backpressure.
actor ControlledEncoder {
    func encode(prepared: PreparedComposition,configuration: ExportConfiguration,duration: CMTime,to url: URL,progress: @Sendable (Float) async -> Void) async throws {
        guard let bitrate = configuration.videoBitrate else { throw RenderError.invalid("A valid video bitrate is required.") }
        let reader = try AVAssetReader(asset: prepared.composition)
        reader.timeRange = CMTimeRange(start: .zero,duration: duration)
        let writer = try AVAssetWriter(outputURL: url,fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        let tracks = try await prepared.composition.loadTracks(withMediaType: .video)
        let video = AVAssetReaderVideoCompositionOutput(videoTracks: tracks,videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,kCVPixelBufferIOSurfacePropertiesKey as String: [:]])
        video.videoComposition = prepared.videoComposition; video.alwaysCopiesSampleData = false
        let settings: [String: Any] = [AVVideoCodecKey: configuration.codec == .hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: configuration.width,AVVideoHeightKey: configuration.height,
            AVVideoEncoderSpecificationKey: [kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String: true],
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate,AVVideoExpectedSourceFrameRateKey: configuration.frameRate.value,AVVideoMaxKeyFrameIntervalDurationKey: 2]]
        guard writer.canApply(outputSettings: settings,forMediaType: .video) else { throw RenderError.invalid("This Mac cannot encode the requested video settings.") }
        let videoInput = AVAssetWriterInput(mediaType: .video,outputSettings: settings)
        videoInput.expectsMediaDataInRealTime = false
        guard reader.canAdd(video), writer.canAdd(videoInput) else { throw RenderError.invalid("Cannot prepare the video encoder.") }
        reader.add(video); writer.add(videoInput)
        var pairs: [(output: AVAssetReaderOutput,input: AVAssetWriterInput,finished: Bool)] = [(video,videoInput,false)]
        let audioTracks = try await prepared.composition.loadTracks(withMediaType: .audio)
        if !audioTracks.isEmpty {
            let audio = AVAssetReaderAudioMixOutput(audioTracks: audioTracks,audioSettings: [AVFormatIDKey: kAudioFormatLinearPCM,AVSampleRateKey: 48000,AVNumberOfChannelsKey: 2,AVLinearPCMBitDepthKey: 32,AVLinearPCMIsFloatKey: true,AVLinearPCMIsNonInterleaved: false])
            audio.audioMix = prepared.audioMix; audio.alwaysCopiesSampleData = false
            let input = AVAssetWriterInput(mediaType: .audio,outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC,AVSampleRateKey: 48000,AVNumberOfChannelsKey: 2,AVEncoderBitRateKey: 320000])
            input.expectsMediaDataInRealTime = false
            guard reader.canAdd(audio), writer.canAdd(input) else { throw RenderError.invalid("Cannot prepare the stereo audio encoder.") }
            reader.add(audio); writer.add(input); pairs.append((audio,input,false))
        }
        do {
            try Task.checkCancellation()
            guard writer.startWriting() else { throw writer.error ?? RenderError.invalid("Cannot start output encoding.") }
            writer.startSession(atSourceTime: .zero)
            guard reader.startReading() else { throw reader.error ?? RenderError.invalid("Cannot read the prepared timeline.") }
            var lastReport = Date.distantPast
            while pairs.contains(where: { !$0.finished }) {
                try Task.checkCancellation()
                if writer.status == .failed { throw writer.error ?? RenderError.invalid("Output encoding failed.") }
                var advanced = false
                for index in pairs.indices where !pairs[index].finished && pairs[index].input.isReadyForMoreMediaData {
                    advanced = true
                    if let sample = pairs[index].output.copyNextSampleBuffer() {
                        guard pairs[index].input.append(sample) else { throw writer.error ?? RenderError.invalid("Cannot encode a timeline sample.") }
                        if index == 0, Date().timeIntervalSince(lastReport) >= 0.1 {
                            lastReport = Date()
                            await progress(Float(min(0.99,max(0,CMSampleBufferGetPresentationTimeStamp(sample).seconds / duration.seconds))))
                        }
                    } else {
                        if reader.status == .failed { throw reader.error ?? RenderError.invalid("Timeline decoding failed.") }
                        pairs[index].input.markAsFinished(); pairs[index].finished = true
                    }
                }
                if !advanced { try await Task.sleep(nanoseconds: 2_000_000) }
                else { await Task.yield() }
            }
            writer.endSession(atSourceTime: duration)
            await writer.finishWriting()
            try Task.checkCancellation()
            guard writer.status == .completed else { throw writer.error ?? RenderError.invalid("Cannot finish the encoded output.") }
        } catch {
            reader.cancelReading(); writer.cancelWriting(); throw error
        }
    }
}
