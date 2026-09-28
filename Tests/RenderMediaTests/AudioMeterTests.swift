import XCTest
import AVFoundation
import RenderCore
@testable import RenderMedia

extension MediaIntegrationTests {
    @MainActor
    func testAudioTapsMeasurePostFaderSamplesWithoutChangingAudio() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("stereo.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000,channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format,frameCapacity: 96000)!; buffer.frameLength = 96000
        for i in 0..<96000 {
            let sample = Float(sin(Double(i) * 440 * 2 * .pi / 48000))
            buffer.floatChannelData![0][i] = sample * 0.4; buffer.floatChannelData![1][i] = sample * 0.2
        }
        do { let file = try AVAudioFile(forWriting: url,settings: format.settings); try file.write(from: buffer) }
        let media = try await MediaLibrary().analyze(url)
        var project = RenderProject(); project.settings.width = 320; project.settings.height = 180; project.assets = [media]
        var clip = TimelineClip(assetID: media.id,name: "Stereo",start: 0,duration: 60); clip.properties.volume = 0.5
        project.tracks[1].clips = [clip]
        let nested = try CompoundEditing.create([clip.id],name: "Audio group",in: project)
        var animated = nested
        let parentLocation = try XCTUnwrap(animated.tracks.indices.first(where: { !animated.tracks[$0].clips.isEmpty }))
        animated.tracks[parentLocation].clips[0].properties.animations["volume"] = AnimationCurve(keys: [Keyframe(frame: 0,value: 0.25),Keyframe(frame: 60,value: 0.75)])
        for (index,edit) in [project,nested,animated].enumerated() {
            let prepared = try await CompositionBuilder().build(edit,metering: true)
            let meter = try XCTUnwrap(prepared.audioMeters.first)
            XCTAssertNil(meter.read(at: 1)); XCTAssertNil(meter.read(at: .nan))
            let reader = try AVAssetReader(asset: prepared.composition)
            let tracks = prepared.composition.tracks.filter { $0.mediaType == .audio }
            let output = AVAssetReaderAudioMixOutput(audioTracks: tracks,audioSettings: [AVFormatIDKey:kAudioFormatLinearPCM,AVLinearPCMBitDepthKey:32,AVLinearPCMIsFloatKey:true,AVLinearPCMIsNonInterleaved:false])
            output.audioMix = prepared.audioMix; reader.add(output)
            XCTAssertTrue(reader.startReading())
            var measured: AudioMeterReading?
            var samplePeak: Float = 0
            while let sample = output.copyNextSampleBuffer() {
                let timestamp = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                if timestamp > 0.2 { measured = meter.read(at: timestamp + 0.001) ?? measured }
                if let block = CMSampleBufferGetDataBuffer(sample) {
                    var length = 0; var data: UnsafeMutablePointer<Int8>?
                    if CMBlockBufferGetDataPointer(block,atOffset: 0,lengthAtOffsetOut: nil,totalLengthOut: &length,dataPointerOut: &data) == kCMBlockBufferNoErr, let data {
                        data.withMemoryRebound(to: Float.self,capacity: length / 4) { values in
                            for i in 0..<(length / 4) { samplePeak = max(samplePeak,abs(values[i])) }
                        }
                    }
                }
            }
            XCTAssertEqual(reader.status,.completed,reader.error?.localizedDescription ?? "")
            let reading = try XCTUnwrap(measured)
            XCTAssertEqual(reading.peaks.count,2)
            let parentGain = index == 2 ? 0.25 + (reading.start + reading.end) / 2 * 0.25 : 1
            XCTAssertEqual(reading.peaks[0],Float(0.2 * parentGain),accuracy: 0.008)
            XCTAssertEqual(reading.peaks[1],Float(0.1 * parentGain),accuracy: 0.008)
            XCTAssertEqual(reading.rms[0],Float(0.2 * parentGain / sqrt(2)),accuracy: 0.008)
            XCTAssertEqual(samplePeak,index == 2 ? 0.15 : 0.2,accuracy: 0.005,"The meter must not alter samples")
            XCTAssertNil(meter.read(at: -1)); XCTAssertNil(meter.read(at: 4))
            let exportComposition = try await CompositionBuilder().build(edit)
            XCTAssertTrue(exportComposition.audioMeters.isEmpty,"Export does not allocate playback meters")
        }
    }
}
