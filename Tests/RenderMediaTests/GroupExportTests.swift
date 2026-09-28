import XCTest
import AVFoundation
import CoreImage
import AppKit
import RenderCore
@testable import RenderMedia

extension MediaIntegrationTests {
    @MainActor
    func testGroupedCompositingMatchesHardwareExport() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = MediaLibrary(), red = try await library.analyze(makeImage(in: folder)), blue = try await library.analyze(makeImage(in: folder,name: "blue.png",color: .blue))
        var project = RenderProject(); project.settings.width = 320; project.settings.height = 180; project.assets = [red,blue]
        let backdrop = TimelineClip(assetID: blue.id,name: "Blue",start: 0,duration: 30)
        project.tracks[0].clips = [backdrop]
        let prepared = try await CompositionBuilder().build(project)
        let clock = try XCTUnwrap(prepared.composition.tracks.first { $0.mediaType == .video }).trackID
        let leaf = RenderLayer(trackID: clock,clip: TimelineClip(assetID: red.id,name: "Red",start: 0,duration: 30),preferredTransform: .identity,still: CIImage(contentsOf: red.url))
        var parent = TimelineClip(assetID: nil,name: "Group",start: 0,duration: 30); parent.properties.scale = 0.5; parent.properties.opacity = 0.5
        let nodes: [RenderNode] = [.group(RenderGroup(clip: parent,children: [.layer(leaf)])),.layer(RenderLayer(trackID: clock,clip: backdrop,preferredTransform: .identity,still: CIImage(contentsOf: blue.url)))]
        prepared.videoComposition.instructions = [RenderInstruction(range: CMTimeRange(start: .zero,duration: CMTime(value: 1,timescale: 1)),nodes: nodes,clock: clock,frameRate: project.settings.frameRate,designSize: CGSize(width: 320,height: 180))]
        let generator = AVAssetImageGenerator(asset: prepared.composition); generator.videoComposition = prepared.videoComposition
        let preview = try await generator.image(at: CMTime(value: 1,timescale: 2)).image
        var config = ExportConfiguration(); config.width = 320; config.height = 180; config.quality = .balanced
        let output = folder.appendingPathComponent("group.mp4")
        try await ControlledEncoder().encode(prepared: prepared,configuration: config,duration: CMTime(value: 1,timescale: 1),to: output) { _ in }
        let encoded = try await AVAssetImageGenerator(asset: AVURLAsset(url: output)).image(at: CMTime(value: 1,timescale: 2)).image
        for point in [CGPoint(x: 150,y: 80),CGPoint(x: 10,y: 10)] {
            let rect = CGRect(origin: point,size: CGSize(width: 16,height: 16))
            let a = pixel(try XCTUnwrap(preview.cropping(to: rect))), b = pixel(try XCTUnwrap(encoded.cropping(to: rect)))
            for channel in 0..<3 { XCTAssertEqual(Double(a[channel]),Double(b[channel]),accuracy: 15) }
            if point.x == 150 { XCTAssertGreaterThan(a[0],100); XCTAssertGreaterThan(a[2],100) }
            else { XCTAssertLessThan(a[0],10); XCTAssertGreaterThan(a[2],220) }
        }
    }
}
