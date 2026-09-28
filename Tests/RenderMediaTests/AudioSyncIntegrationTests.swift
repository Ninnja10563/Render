import XCTest
import AVFoundation
import RenderCore
@testable import RenderMedia

extension MediaIntegrationTests {
    func testSyncDecodesSourceInAndFindsRecordingOffset() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var seed: UInt64 = 13
        let amplitudes: [Float] = (0..<500).map { _ in
            seed = seed &* 6364136223846793005 &+ 1
            return 0.05 + Float((seed >> 32) % 1000) / 2500
        }
        func write(_ name: String,offset: Int,gain: Float) throws -> URL {
            let url = folder.appendingPathComponent(name + ".wav")
            let format = AVAudioFormat(standardFormatWithSampleRate: 48000,channels: 2)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format,frameCapacity: 192000)!
            buffer.frameLength = 192000
            for index in 0..<192000 {
                let value = Float(sin(Double(index) * 1000 * 2 * .pi / 48000)) * amplitudes[index / 480 + offset] * gain
                buffer.floatChannelData![0][index] = value
                buffer.floatChannelData![1][index] = -value // RMS preserves opposite-polarity stereo energy.
            }
            let file = try AVAudioFile(forWriting: url,settings: format.settings); try file.write(from: buffer)
            return url
        }
        let aURL = try write("reference",offset: 0,gain: 1), bURL = try write("target",offset: 37,gain: 0.5)
        let library = MediaLibrary(), a = try await library.analyze(aURL), b = try await library.analyze(bURL)
        var reference = TimelineClip(assetID: a.id,name: "Reference",start: 90,duration: 90)
        reference.sourceIn = 0.2
        let target = TimelineClip(assetID: b.id,name: "Target",start: 0,duration: 90)
        let result = try await AudioSyncAnalyzer().analyze(reference: a,referenceClip: reference,target: b,targetClip: target,rate: FrameRate())
        XCTAssertEqual(result.offset,17)
        XCTAssertGreaterThan(result.correlation,0.98)
        var project = RenderProject(); project.assets = [a,b]
        project.tracks = [TimelineTrack(name: "Reference",kind: .audio),TimelineTrack(name: "Target",kind: .audio)]
        project.tracks[0].clips = [reference]; project.tracks[1].clips = [target]
        let destination = reference.start + project.settings.frameRate.frames(Double(result.offset) / 100)
        let transaction = try ProjectTransaction(.move(clips: [target.id],delta: destination - target.start),project: project)
        XCTAssertEqual(transaction.after.clip(target.id)?.start,95)
        XCTAssertEqual(transaction.before,project)
    }
}
