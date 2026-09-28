import XCTest
import AVFoundation
import RenderCore
@testable import RenderMedia

extension MediaIntegrationTests {
    @MainActor
    func testReducedResolutionPreviewPreservesCompositionAndFullSizeExport() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = MediaLibrary(), media = try await library.analyze(makeImage(in: folder))
        var project = RenderProject(); project.settings.width = 320; project.settings.height = 180; project.assets = [media]
        var clip = TimelineClip(assetID: media.id,name: "Quality",start: 0,duration: 15); clip.properties.scale = 0.5
        project.tracks[0].clips = [clip]
        let nested = try CompoundEditing.create([clip.id],name: "Nested quality",in: project)
        for edit in [project,nested] {
            for quality in PreviewQuality.allCases {
                let dims = quality.dimensions(for: edit.settings)
                let built = try await CompositionBuilder().build(edit,outputSize: CGSize(width: dims.width,height: dims.height))
                XCTAssertEqual(built.videoComposition.renderSize,CGSize(width: dims.width,height: dims.height))
                let generator = AVAssetImageGenerator(asset: built.composition); generator.videoComposition = built.videoComposition
                generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
                let frame = try await generator.image(at: CMTime(value: 6,timescale: 30)).image
                XCTAssertEqual(frame.width,dims.width); XCTAssertEqual(frame.height,dims.height)
                let center = pixel(try XCTUnwrap(frame.cropping(to: CGRect(x: dims.width / 2 - 2,y: dims.height / 2 - 2,width: 4,height: 4))))
                XCTAssertGreaterThan(center[0],240)
                let edge = pixel(try XCTUnwrap(frame.cropping(to: CGRect(x: 1,y: 1,width: 2,height: 2))))
                XCTAssertLessThan(edge[0],5)
            }
        }
        var config = ExportConfiguration(); config.width = 320; config.height = 180
        let url = folder.appendingPathComponent("full.mp4")
        try await ExportService().export(project: nested,configuration: config,to: url)
        let output = try await library.analyze(url)
        XCTAssertEqual(output.width,320); XCTAssertEqual(output.height,180)
        var tiny = ProjectSettings(); tiny.width = 2; tiny.height = 2
        XCTAssertEqual(PreviewQuality.quarter.dimensions(for: tiny).width,2)
        var oddDivision = ProjectSettings(); oddDivision.width = 854; oddDivision.height = 480
        XCTAssertEqual(PreviewQuality.quarter.dimensions(for: oddDivision).width,212)
    }
}
