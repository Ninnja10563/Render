import XCTest
import AVFoundation
import AppKit
import RenderCore
@testable import RenderMedia

extension MediaIntegrationTests {
    @MainActor
    func testFilmstripSamplesSourceTimeAndPersistsAcrossReaders() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cacheFolder = folder.appendingPathComponent("derived")
        let library = MediaLibrary(cacheFolder: cacheFolder)
        let red = try await library.analyze(makeImage(in: folder))
        let blue = try await library.analyze(makeImage(in: folder,name: "blue.png",color: .blue))
        var project = RenderProject(); project.settings.width = 320; project.settings.height = 180; project.assets = [red,blue]
        project.tracks[0].clips = [TimelineClip(assetID: red.id,name: "Red",start: 0,duration: 30),TimelineClip(assetID: blue.id,name: "Blue",start: 30,duration: 30)]
        var config = ExportConfiguration(); config.width = 320; config.height = 180
        let output = folder.appendingPathComponent("sequence.mp4")
        try await ExportService().export(project: project,configuration: config,to: output)
        let video = try await library.analyze(output)
        let frames = try await library.filmstrip(video,seconds: [0.2,1.5,0.2])
        XCTAssertEqual(frames.count,3); XCTAssertLessThanOrEqual(frames[0].width,160)
        XCTAssertGreaterThan(pixel(frames[0])[0],200)
        XCTAssertGreaterThan(pixel(frames[1])[2],200)
        XCTAssertGreaterThan(pixel(frames[2])[0],200)
        let persisted = try await MediaLibrary(cacheFolder: cacheFolder).filmstrip(video,seconds: [1.5,0.2])
        XCTAssertEqual(persisted.count,2)
        XCTAssertGreaterThan(pixel(persisted[0])[2],200); XCTAssertGreaterThan(pixel(persisted[1])[0],200)
        do { _ = try await library.filmstrip(video,seconds: [.nan]); XCTFail("Nonfinite source time accepted") } catch {}
        do { _ = try await library.filmstrip(video,seconds: Array(repeating: 0,count: 129)); XCTFail("Unbounded request accepted") } catch {}
        let cancelled = Task { try await library.filmstrip(video,seconds: [0.7,1.7]) }
        cancelled.cancel()
        do { _ = try await cancelled.value; XCTFail("Cancelled decoder request completed") } catch {}
        let after = try await library.filmstrip(video,seconds: [0.7])
        XCTAssertEqual(after.count,1) // Cancellation released the decoder permit.
    }
}
