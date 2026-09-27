import XCTest
import AVFoundation
import AppKit
import RenderCore
@testable import RenderMedia

extension MediaIntegrationTests {
    @MainActor
    func testKeyedAndMaskedCompositionPreviewExportParity() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = MediaLibrary()
        let green = try await library.analyze(makeImage(in: folder,name: "green.png",color: .green))
        let blue = try await library.analyze(makeImage(in: folder,name: "blue.png",color: .blue))
        var project = RenderProject(); project.settings.width = 320; project.settings.height = 180; project.assets = [green,blue]
        var top = TimelineClip(assetID: green.id,name: "Screen",start: 0,duration: 6)
        var key = Effect(kind: .chromaKey); var mask = EffectMask()
        mask.shape = .rectangle; mask.width = 0.5; mask.height = 1; mask.x = 0.25; mask.feather = 0
        key.mask = mask; top.effects = [key]; project.tracks[0].clips = [top]
        var lower = TimelineTrack(name: "Background",kind: .video)
        lower.clips = [TimelineClip(assetID: blue.id,name: "Blue",start: 0,duration: 6)]
        project.tracks.insert(lower,at: 1)
        let prepared = try await CompositionBuilder().build(project)
        let generator = AVAssetImageGenerator(asset: prepared.composition); generator.videoComposition = prepared.videoComposition
        let preview = try await generator.image(at: CMTime(value: 1,timescale: 30)).image
        var config = ExportConfiguration(); config.width = 320; config.height = 180
        let output = folder.appendingPathComponent("keyed.mp4")
        try await ExportService().export(project: project,configuration: config,to: output)
        let encoded = try await AVAssetImageGenerator(asset: AVURLAsset(url: output)).image(at: CMTime(value: 1,timescale: 30)).image
        for x in [40,240] {
            let rect = CGRect(x: x,y: 60,width: 16,height: 16)
            let a = pixel(try XCTUnwrap(preview.cropping(to: rect)))
            let b = pixel(try XCTUnwrap(encoded.cropping(to: rect)))
            XCTAssertGreaterThan(a[x == 40 ? 2 : 1],220)
            XCTAssertLessThan(a[x == 40 ? 1 : 2],30)
            for channel in 0..<3 { XCTAssertEqual(Double(a[channel]),Double(b[channel]),accuracy: 15) }
        }
    }
}
