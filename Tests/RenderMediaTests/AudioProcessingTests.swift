import XCTest
import AVFoundation
import RenderCore
@testable import RenderMedia

extension MediaIntegrationTests {
    @MainActor
    func testAudioEffectsReachReaderAndEveryExportPath() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("tone.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000,channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format,frameCapacity: 96000)!; buffer.frameLength = 96000
        for i in 0..<96000 {
            let sample = Float(sin(Double(i) * 1000 * 2 * .pi / 48000))
            buffer.floatChannelData![0][i] = sample * 0.4
            buffer.floatChannelData![1][i] = sample * 0.2
        }
        do { let file = try AVAudioFile(forWriting: url,settings: format.settings); try file.write(from: buffer) }
        let library = MediaLibrary(), media = try await library.analyze(url)
        var project = RenderProject(); project.settings.width = 320; project.settings.height = 180; project.assets = [media]
        var clip = TimelineClip(assetID: media.id,name: "Processed",start: 0,duration: 60)
        var effect = AudioEffect(kind: .equalizer); effect.values["midGain"] = -12
        clip.properties.audioEffects = [effect]; project.tracks[1].clips = [clip]
        let nested = try CompoundEditing.create([clip.id],name: "Audio group",in: project)
        for edit in [project,nested] {
            let prepared = try await CompositionBuilder().build(edit,metering: true)
            XCTAssertEqual(prepared.audioProcessing.count,1)
            let peaks = try readProcessedPeaks(prepared)
            XCTAssertEqual(peaks[0],0.4 * pow(10,-0.6),accuracy: 0.003)
            XCTAssertEqual(peaks[1],0.2 * pow(10,-0.6),accuracy: 0.003)
            try prepared.checkAudioProcessing()
        }
        for (index,codec) in [ExportCodec.h264,.hevc,.proRes,.h264,.hevc].enumerated() {
            var config = ExportConfiguration(); config.width = 320; config.height = 180; config.codec = codec
            if index >= 3 { config.quality = .balanced }
            let output = folder.appendingPathComponent("processed-\(index).\(codec == .proRes ? "mov" : "mp4")")
            try await ExportService().export(project: nested,configuration: config,to: output)
            let exported = try await library.analyze(output)
            let waveform = try await library.waveform(exported,bins: 100)
            XCTAssertEqual(Double(waveform[30..<80].max() ?? 0),0.4 * pow(10,-0.6),accuracy: 0.018,"Export path \(index) must apply the audio stack")
        }
        project.tracks[1].clips[0].properties.audioEffects![0].enabled = false
        let bypassed = try await CompositionBuilder().build(project)
        XCTAssertTrue(bypassed.audioProcessing.isEmpty)
        XCTAssertEqual(try readProcessedPeaks(bypassed)[0],0.4,accuracy: 0.002)
    }

    private func readProcessedPeaks(_ prepared: PreparedComposition) throws -> [Double] {
        let reader = try AVAssetReader(asset: prepared.composition)
        let output = AVAssetReaderAudioMixOutput(audioTracks: prepared.composition.tracks.filter { $0.mediaType == .audio },audioSettings: [AVFormatIDKey:kAudioFormatLinearPCM,AVSampleRateKey:48000,AVNumberOfChannelsKey:2,AVLinearPCMBitDepthKey:32,AVLinearPCMIsFloatKey:true,AVLinearPCMIsNonInterleaved:false])
        output.audioMix = prepared.audioMix; reader.add(output); XCTAssertTrue(reader.startReading())
        var peaks = [Double](repeating: 0,count: 2)
        while let sample = output.copyNextSampleBuffer() {
            guard CMSampleBufferGetPresentationTimeStamp(sample).seconds > 0.5,let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            var length = 0; var data: UnsafeMutablePointer<Int8>?
            guard CMBlockBufferGetDataPointer(block,atOffset: 0,lengthAtOffsetOut: nil,totalLengthOut: &length,dataPointerOut: &data) == kCMBlockBufferNoErr,let data else { continue }
            data.withMemoryRebound(to: Float.self,capacity: length / 4) { values in
                for i in 0..<(length / 4) { peaks[i % 2] = max(peaks[i % 2],Double(abs(values[i]))) }
            }
        }
        XCTAssertEqual(reader.status,.completed,reader.error?.localizedDescription ?? "")
        return peaks
    }
}
