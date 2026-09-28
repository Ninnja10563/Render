import XCTest
import AVFoundation
import AppKit
import RenderCore
@testable import RenderMedia

extension MediaIntegrationTests {
    @MainActor
    func testBitrateExportRetainsCompositorAudioAndFrameRate() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = MediaLibrary(), red = try await library.analyze(makeImage(in: folder))
        let audioURL = folder.appendingPathComponent("tone.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000,channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format,frameCapacity: 48000)!
        buffer.frameLength = 48000
        for index in 0..<48000 { buffer.floatChannelData![0][index] = Float(sin(Double(index) * 440 * 2 * .pi / 48000)) * 0.4 }
        do { let file = try AVAudioFile(forWriting: audioURL,settings: format.settings); try file.write(from: buffer) }
        let audio = try await library.analyze(audioURL)
        var project = RenderProject(); project.settings.width = 320; project.settings.height = 180; project.assets = [red,audio]
        var visual = TimelineClip(assetID: red.id,name: "Transformed",start: 0,duration: 30); visual.properties.scale = 0.5
        project.tracks[0].clips = [visual]
        var sound = TimelineClip(assetID: audio.id,name: "Quiet",start: 0,duration: 30); sound.properties.volume = 0.5
        project.tracks[1].clips = [sound]
        for codec in [ExportCodec.h264,.hevc] {
            var config = ExportConfiguration(); config.width = 320; config.height = 180; config.frameRate = FrameRate(24); config.codec = codec; config.quality = .custom; config.customBitrateMbps = 2
            let output = folder.appendingPathComponent("\(codec.rawValue).mp4")
            let service = ExportService()
            try await service.export(project: project,configuration: config,to: output)
            XCTAssertEqual(service.progress,1); XCTAssertFalse(service.isExporting)
            let result = try await library.analyze(output)
            XCTAssertEqual(result.width,320); XCTAssertEqual(result.height,180); XCTAssertEqual(result.frameRate,24,accuracy: 0.1)
            XCTAssertEqual(result.duration,1,accuracy: 0.06); XCTAssertEqual(result.audioChannels,2)
            let peaks = try await library.waveform(result,bins: 100)
            XCTAssertEqual(Double(peaks[20..<80].max() ?? 0),0.2,accuracy: 0.04)
            let image = try await AVAssetImageGenerator(asset: AVURLAsset(url: output)).image(at: CMTime(value: 1,timescale: 2)).image
            let center = pixel(try XCTUnwrap(image.cropping(to: CGRect(x: 150,y: 80,width: 16,height: 16))))
            let edge = pixel(try XCTUnwrap(image.cropping(to: CGRect(x: 0,y: 0,width: 16,height: 16))))
            XCTAssertGreaterThan(center[0],230); XCTAssertLessThan(edge[0],15)
        }
    }
    @MainActor
    func testCancelledBitrateExportDoesNotPublishPartialFile() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let media = try await MediaLibrary().analyze(makeImage(in: folder))
        var project = RenderProject(); project.assets = [media]
        project.tracks[0].clips = [TimelineClip(assetID: media.id,name: "Long",start: 0,duration: 18000)]
        var config = ExportConfiguration(); config.quality = .balanced
        let service = ExportService(), output = folder.appendingPathComponent("cancelled.mp4")
        let task = Task { try await service.export(project: project,configuration: config,to: output) }
        try await Task.sleep(nanoseconds: 300_000_000); service.cancel()
        do { try await task.value; XCTFail("Export should have been cancelled") } catch is CancellationError {} catch { XCTFail("Unexpected cancellation error: \(error)") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertFalse(service.isExporting)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: folder.path).contains { $0.hasPrefix(".render-export") })
    }
}
