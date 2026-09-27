import XCTest
import AVFoundation
import AppKit
import RenderCore
@testable import RenderMedia

extension MediaIntegrationTests {
    @MainActor
    func testTransitionsDecodeOverlappingVideoHandlesAndMatchExport() async throws {
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
            fixture.tracks[0].clips = [TimelineClip(assetID: media.id,name: media.name,start: 0,duration: 60)]
            let url = folder.appendingPathComponent(media.name + ".mp4")
            try await ExportService().export(project: fixture,configuration: config,to: url)
            sources.append(try await library.analyze(url))
        }
        var project = RenderProject(); project.settings = fixture.settings; project.assets = sources
        var a = TimelineClip(assetID: sources[0].id,name: "Red video",start: 0,duration: 30); a.sourceIn = 0.5
        var b = TimelineClip(assetID: sources[1].id,name: "Blue video",start: 30,duration: 30); b.sourceIn = 0.5
        project.tracks[0].clips = [a,b]
        for kind in TransitionKind.allCases {
            project = try TimelineCommand.transition(clip: a.id,ClipTransition(rightID: b.id,kind: kind,duration: 12)).applying(to: project)
            let built = try await CompositionBuilder().build(project)
            XCTAssertEqual(built.composition.tracks.filter { $0.mediaType == .video }.count,3)
            XCTAssertEqual(built.composition.duration.seconds,2,accuracy: 0.01)
            let generator = AVAssetImageGenerator(asset: built.composition); generator.videoComposition = built.videoComposition
            generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
            let output = folder.appendingPathComponent(kind.rawValue + ".mp4")
            try await ExportService().export(project: project,configuration: config,to: output)
            let encoded = AVAssetImageGenerator(asset: AVURLAsset(url: output))
            encoded.requestedTimeToleranceBefore = .zero; encoded.requestedTimeToleranceAfter = .zero
            for frame: Int64 in [24,30,36] {
                let time = CMTime(value: frame,timescale: 30)
                let preview = try await generator.image(at: time).image
                let exported = try await encoded.image(at: time).image
                for x in [40,240] {
                    let rect = CGRect(x: x,y: 70,width: 16,height: 16)
                    let p = pixel(try XCTUnwrap(preview.cropping(to: rect))), e = pixel(try XCTUnwrap(exported.cropping(to: rect)))
                    for channel in 0..<3 { XCTAssertEqual(Double(p[channel]),Double(e[channel]),accuracy: 15,"\(kind) frame \(frame)") }
                    if frame == 24 { XCTAssertGreaterThan(p[0],220); XCTAssertLessThan(p[2],30) }
                    if frame == 36 { XCTAssertGreaterThan(p[2],220); XCTAssertLessThan(p[0],30) }
                    if kind == .crossDissolve && frame == 30 { XCTAssertGreaterThan(p[0],100); XCTAssertGreaterThan(p[2],100) }
                }
            }
        }
    }
}
