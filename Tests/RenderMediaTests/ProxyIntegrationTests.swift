import XCTest
import AVFoundation
import AppKit
import RenderCore
@testable import RenderMedia

extension MediaIntegrationTests {
    @MainActor
    func testGeneratedMediaPlaybackAndOriginalOnlyExport() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = MediaLibrary()
        let red = try await library.analyze(makeImage(in: folder))
        let blue = try await library.analyze(makeImage(in: folder,name: "blue.png",color: .blue))
        var config = ExportConfiguration(); config.width = 320; config.height = 180
        var sourceProject = RenderProject(); sourceProject.settings.width = 320; sourceProject.settings.height = 180
        sourceProject.assets = [red]
        sourceProject.tracks[0].clips = [TimelineClip(assetID: red.id,name: "Original",start: 0,duration: 6)]
        let originalURL = folder.appendingPathComponent("original.mov")
        config.codec = .proRes
        try await ExportService().export(project: sourceProject,configuration: config,to: originalURL)
        var original = try await library.analyze(originalURL)
        let generator = MediaTranscoder()
        let proxy = try await generator.generate(original,mode: .proxy,in: folder)
        let optimized = try await generator.generate(original,mode: .optimized,in: folder)
        let proxyMedia = try await library.analyze(proxy.url)
        XCTAssertLessThanOrEqual(proxyMedia.width,1280)
        XCTAssertEqual(proxyMedia.duration,original.duration,accuracy: 0.04)
        XCTAssertTrue(FileManager.default.fileExists(atPath: optimized.url.path))
        original.variants = [proxy,optimized]
        var project = RenderProject(); project.settings = sourceProject.settings; project.assets = [original]
        project.tracks[0].clips = [TimelineClip(assetID: original.id,name: "With variants",start: 0,duration: 6)]
        for mode in [PlaybackMediaMode.proxy,.optimized] {
            let built = try await CompositionBuilder().build(project,mode: mode)
            XCTAssertTrue(built.originalFallbacks.isEmpty)
        }
        // Deliberately substitute a blue proxy to prove export ignores playback representations.
        sourceProject.assets = [blue]; sourceProject.tracks[0].clips[0].assetID = blue.id
        let blueURL = folder.appendingPathComponent("blue.mov")
        try await ExportService().export(project: sourceProject,configuration: config,to: blueURL)
        project.assets[0].variants = [MediaVariant(mode: .proxy,url: blueURL,source: try SourceFingerprint(url: originalURL))]
        let built = try await CompositionBuilder().build(project,mode: .proxy)
        let preview = AVAssetImageGenerator(asset: built.composition); preview.videoComposition = built.videoComposition
        let proxyPixel = pixel(try await preview.image(at: CMTime(value: 1,timescale: 30)).image)
        XCTAssertGreaterThan(proxyPixel[2],200); XCTAssertLessThan(proxyPixel[0],40)
        let final = folder.appendingPathComponent("final.mov")
        try await ExportService().export(project: project,configuration: config,to: final)
        let outputPixel = pixel(try await AVAssetImageGenerator(asset: AVURLAsset(url: final)).image(at: CMTime(value: 1,timescale: 30)).image)
        XCTAssertGreaterThan(outputPixel[0],200); XCTAssertLessThan(outputPixel[2],40)
        // Corrupt cached files must fall back instead of breaking a valid original timeline.
        try Data("broken proxy".utf8).write(to: blueURL)
        let fallback = try await CompositionBuilder().build(project,mode: .proxy)
        XCTAssertEqual(fallback.originalFallbacks,[original.name])
    }
    @MainActor
    func testQueuedTaskCancellationAndFailureRemainObservable() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let queue = BackgroundTasks(folder: folder)
        let cancelled = expectation(description: "Queued task cancelled")
        let unsupported = expectation(description: "Unsupported request failed")
        let video = MediaAsset(url: URL(fileURLWithPath: "/missing.mov"),kind: .video,duration: 1)
        let id = queue.enqueue(video,mode: .proxy) { result in
            if case .failure(let error) = result { XCTAssertTrue(error is CancellationError); cancelled.fulfill() }
        }
        queue.cancel(id)
        let image = MediaAsset(url: URL(fileURLWithPath: "/image.png"),kind: .image,duration: 5)
        queue.enqueue(image,mode: .proxy) { result in
            if case .failure = result { unsupported.fulfill() }
        }
        await fulfillment(of: [cancelled,unsupported],timeout: 5)
        XCTAssertEqual(queue.tasks.map(\.state),[.cancelled,.failed])
        XCTAssertEqual(queue.activeCount,0)
        queue.clearFinished(); XCTAssertTrue(queue.tasks.isEmpty)
    }
}
