import XCTest
import AVFoundation
import AppKit
import RenderCore
@testable import RenderMedia

extension MediaIntegrationTests {
    @MainActor
    func testCroppedFlippedScreenBlendMatchesExport() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = MediaLibrary()
        let red = try await library.analyze(makeImage(in: folder))
        let blue = try await library.analyze(makeImage(in: folder,name: "blue.png",color: .blue))
        var project = RenderProject(); project.settings.width = 320; project.settings.height = 180; project.assets = [red,blue]
        var top = TimelineClip(assetID: red.id,name: "Crop and screen",start: 0,duration: 6)
        var geometry = ClipGeometry(); geometry.scaleX = 0.8; geometry.scaleY = 0.6; geometry.cropLeft = 0.5; geometry.flipHorizontal = true; geometry.blend = .screen
        top.properties.geometry = geometry; project.tracks[0].clips = [top]
        var lower = TimelineTrack(name: "Background",kind: .video); lower.clips = [TimelineClip(assetID: blue.id,name: "Blue",start: 0,duration: 6)]
        project.tracks.insert(lower,at: 1)
        let built = try await CompositionBuilder().build(project)
        let generator = AVAssetImageGenerator(asset: built.composition); generator.videoComposition = built.videoComposition
        let preview = try await generator.image(at: CMTime(value: 1,timescale: 30)).image
        var config = ExportConfiguration(); config.width = 320; config.height = 180
        let output = folder.appendingPathComponent("geometry.mp4")
        try await ExportService().export(project: project,configuration: config,to: output)
        let encoded = try await AVAssetImageGenerator(asset: AVURLAsset(url: output)).image(at: CMTime(value: 1,timescale: 30)).image
        for x in [80,240] {
            let rect = CGRect(x: x,y: 80,width: 16,height: 16)
            let a = pixel(try XCTUnwrap(preview.cropping(to: rect))), b = pixel(try XCTUnwrap(encoded.cropping(to: rect)))
            XCTAssertGreaterThan(a[2],230); XCTAssertLessThan(a[1],20)
            if x == 80 { XCTAssertGreaterThan(a[0],230) } else { XCTAssertLessThan(a[0],20) }
            for channel in 0..<3 { XCTAssertEqual(Double(a[channel]),Double(b[channel]),accuracy: 15) }
        }
    }
}
