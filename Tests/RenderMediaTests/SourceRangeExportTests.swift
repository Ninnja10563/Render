import XCTest
import AVFoundation
import AppKit
import RenderCore
@testable import RenderMedia

extension MediaIntegrationTests {
    @MainActor
    func testMarkedSourceRangeMatchesPreviewAndExportedFrames() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = MediaLibrary()
        let red = try await library.analyze(makeImage(in: folder,name: "red.png",color: .red))
        let blue = try await library.analyze(makeImage(in: folder,name: "blue.png",color: .blue))
        var sourceProject = RenderProject(); sourceProject.settings.width = 320; sourceProject.settings.height = 180; sourceProject.assets = [red,blue]
        sourceProject.tracks[0].clips = [TimelineClip(assetID: red.id,name: "Red",start: 0,duration: 30),TimelineClip(assetID: blue.id,name: "Blue",start: 30,duration: 30)]
        var config = ExportConfiguration(); config.width = 320; config.height = 180
        let sourceURL = folder.appendingPathComponent("source.mp4")
        try await ExportService().export(project: sourceProject,configuration: config,to: sourceURL)
        let source = try await library.analyze(sourceURL)
        var edit = RenderProject(); edit.settings = sourceProject.settings; edit.assets = [source]
        edit = try TimelineCommand.sourceSelection(asset: source.id,.init(start: 1,end: 2)).applying(to: edit)
        edit = try TimelineCommand.append(asset: source.id,track: edit.tracks[0].id,at: 0).applying(to: edit)
        let prepared = try await CompositionBuilder().build(edit)
        let preview = AVAssetImageGenerator(asset: prepared.composition); preview.videoComposition = prepared.videoComposition
        preview.requestedTimeToleranceBefore = .zero; preview.requestedTimeToleranceAfter = .zero
        let output = folder.appendingPathComponent("range.mp4")
        try await ExportService().export(project: edit,configuration: config,to: output)
        let result = try await library.analyze(output); XCTAssertEqual(result.duration,1,accuracy: 0.04)
        let exported = AVAssetImageGenerator(asset: AVURLAsset(url: output)); exported.requestedTimeToleranceBefore = .zero; exported.requestedTimeToleranceAfter = .zero
        for seconds in [0.0,0.9] {
            let time = CMTime(seconds: seconds,preferredTimescale: 600)
            let a = pixel(try await preview.image(at: time).image),b = pixel(try await exported.image(at: time).image)
            XCTAssertLessThan(a[0],30); XCTAssertGreaterThan(a[2],180)
            XCTAssertLessThan(b[0],30); XCTAssertGreaterThan(b[2],180)
        }
    }
}
