import XCTest
import AVFoundation
import AppKit
import RenderCore
@testable import RenderMedia

extension MediaIntegrationTests {
    @MainActor
    func testNestedVideoHandlesRetimingProxyFallbackAndOriginalExport() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = MediaLibrary()
        let red = try await library.analyze(makeImage(in: folder)), blue = try await library.analyze(makeImage(in: folder,name: "blue.png",color: .blue))
        var settings = ProjectSettings(); settings.width = 320; settings.height = 180
        var config = ExportConfiguration(); config.width = 320; config.height = 180; config.quality = .balanced
        var fixture = RenderProject(); fixture.settings = settings; fixture.assets = [red,blue]
        var sources: [MediaAsset] = []
        for media in [red,blue] {
            fixture.tracks[0].clips = [TimelineClip(assetID: media.id,name: media.name,start: 0,duration: 90)]
            let url = folder.appendingPathComponent(media.name + ".mp4")
            try await ExportService().export(project: fixture,configuration: config,to: url)
            sources.append(try await library.analyze(url))
        }
        var project = RenderProject(); project.settings = settings; project.assets = sources
        var a = TimelineClip(assetID: sources[0].id,name: "Red",start: 0,duration: 30); a.sourceIn = 0.5
        var b = TimelineClip(assetID: sources[1].id,name: "Blue",start: 30,duration: 30); b.sourceIn = 0.5
        a.transition = ClipTransition(rightID: b.id,kind: .crossDissolve,duration: 12)
        project.tracks[0].clips = [a,b]
        project = try CompoundEditing.create([a.id,b.id],name: "Transition Scene",in: project)
        let inner = try XCTUnwrap(project.tracks.flatMap(\.clips).first)
        project = try CompoundEditing.create([inner.id],name: "Nested Scene",in: project)
        let outer = try XCTUnwrap(project.tracks.flatMap(\.clips).first)
        project = try TimelineCommand.speed(clip: outer.id,2).applying(to: project)
        let built = try await CompositionBuilder().build(project)
        XCTAssertEqual(built.composition.tracks.filter { $0.mediaType == .video }.count,3)
        XCTAssertEqual(built.composition.duration.seconds,1,accuracy: 0.001)
        let preview = AVAssetImageGenerator(asset: built.composition); preview.videoComposition = built.videoComposition
        preview.requestedTimeToleranceBefore = .zero; preview.requestedTimeToleranceAfter = .zero
        let output = folder.appendingPathComponent("nested-video.mp4")
        try await ExportService().export(project: project,configuration: config,to: output)
        let encoded = AVAssetImageGenerator(asset: AVURLAsset(url: output)); encoded.requestedTimeToleranceBefore = .zero; encoded.requestedTimeToleranceAfter = .zero
        for frame: Int64 in [6,12,15,18,24] {
            let time = CMTime(value: frame,timescale: 30)
            let p = pixel(try await preview.image(at: time).image), e = pixel(try await encoded.image(at: time).image)
            for channel in 0..<3 { XCTAssertEqual(Double(p[channel]),Double(e[channel]),accuracy: 15) }
            if frame == 6 { XCTAssertGreaterThan(p[0],220); XCTAssertLessThan(p[2],20) }
            if frame == 15 { XCTAssertGreaterThan(p[0],100); XCTAssertGreaterThan(p[2],100) }
            if frame == 24 { XCTAssertGreaterThan(p[2],220); XCTAssertLessThan(p[0],20) }
        }
        // A visibly different proxy proves nested final export reconnects the original.
        project.assets[0].variants = [MediaVariant(mode: .proxy,url: sources[1].url,source: try SourceFingerprint(url: sources[0].url))]
        let proxy = try await CompositionBuilder().build(project,mode: .proxy)
        let proxyFrames = AVAssetImageGenerator(asset: proxy.composition); proxyFrames.videoComposition = proxy.videoComposition
        proxyFrames.requestedTimeToleranceBefore = .zero; proxyFrames.requestedTimeToleranceAfter = .zero
        let proxyPixel = pixel(try await proxyFrames.image(at: CMTime(value: 6,timescale: 30)).image)
        XCTAssertGreaterThan(proxyPixel[2],220); XCTAssertLessThan(proxyPixel[0],20)
        let finalURL = folder.appendingPathComponent("original-only.mp4")
        try await ExportService().export(project: project,configuration: config,to: finalURL)
        let finalFrames = AVAssetImageGenerator(asset: AVURLAsset(url: finalURL)); finalFrames.requestedTimeToleranceBefore = .zero; finalFrames.requestedTimeToleranceAfter = .zero
        let finalPixel = pixel(try await finalFrames.image(at: CMTime(value: 6,timescale: 30)).image)
        XCTAssertGreaterThan(finalPixel[0],220); XCTAssertLessThan(finalPixel[2],20)
        let badURL = folder.appendingPathComponent("broken.mov"); try Data("invalid".utf8).write(to: badURL)
        project.assets[0].variants![0].url = badURL
        let fallback = try await CompositionBuilder().build(project,mode: .proxy)
        XCTAssertTrue(fallback.originalFallbacks.contains(sources[0].name))
    }
}
