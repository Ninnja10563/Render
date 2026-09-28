import XCTest
import AVFoundation
import AppKit
import RenderCore
@testable import RenderMedia

extension MediaIntegrationTests {
    @MainActor
    func testMulticamCutsDecodeChosenSourcesInPreviewAndExport() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = MediaLibrary()
        let red = try await library.analyze(makeImage(in: folder))
        let blue = try await library.analyze(makeImage(in: folder,name: "blue.png",color: .blue))
        var config = ExportConfiguration(); config.width = 320; config.height = 180
        var fixture = RenderProject(); fixture.settings.width = 320; fixture.settings.height = 180; fixture.assets = [red,blue]
        var sources: [MediaAsset] = []
        for media in [red,blue] {
            fixture.tracks[0].clips = [TimelineClip(assetID: media.id,name: media.name,start: 0,duration: 90)]
            let url = folder.appendingPathComponent(media.name + ".mp4")
            try await ExportService().export(project: fixture,configuration: config,to: url)
            sources.append(try await library.analyze(url))
        }
        var project = RenderProject(); project.settings = fixture.settings; project.assets = sources
        var clip = TimelineClip(assetID: sources[0].id,name: "Interview",start: 0,duration: 60); clip.sourceIn = 0.2
        project.tracks[0].clips = [clip]
        let cameras = MulticamSource(name: "Interview",angles: [CameraAngle(name: "A",assetID: sources[0].id),CameraAngle(name: "B",assetID: sources[1].id,offset: 0.3)])
        project = try TimelineCommand.makeMulticam(clip: clip.id,cameras).applying(to: project)
        project = try TimelineCommand.switchAngle(clip: clip.id,angle: cameras.angles[1].id,at: 30).applying(to: project)
        XCTAssertEqual(project.tracks[0].clips.last?.sourceIn ?? -1,1.5,accuracy: 0.001)
        let prepared = try await CompositionBuilder().build(project)
        let preview = AVAssetImageGenerator(asset: prepared.composition); preview.videoComposition = prepared.videoComposition
        preview.requestedTimeToleranceBefore = .zero; preview.requestedTimeToleranceAfter = .zero
        config.quality = .balanced
        let output = folder.appendingPathComponent("multicam.mp4")
        try await ExportService().export(project: project,configuration: config,to: output)
        let encoded = AVAssetImageGenerator(asset: AVURLAsset(url: output))
        encoded.requestedTimeToleranceBefore = .zero; encoded.requestedTimeToleranceAfter = .zero
        for (frame,channel) in [(15,0),(45,2)] {
            let time = CMTime(value: Int64(frame),timescale: 30)
            let a = pixel(try await preview.image(at: time).image), b = pixel(try await encoded.image(at: time).image)
            XCTAssertGreaterThan(a[channel],220)
            for index in 0..<3 { XCTAssertEqual(Double(a[index]),Double(b[index]),accuracy: 15) }
        }
    }
}
