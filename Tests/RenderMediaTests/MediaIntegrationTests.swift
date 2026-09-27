import XCTest
import AVFoundation
import AppKit
@testable import RenderMedia
import RenderCore

final class MediaIntegrationTests: XCTestCase {
    func makeImage(in folder: URL, name: String = "red.png", color: NSColor = .red) throws -> URL {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,pixelsWide: 320,pixelsHigh: 180,bitsPerSample: 8,samplesPerPixel: 4,hasAlpha: true,isPlanar: false,colorSpaceName: .deviceRGB,bytesPerRow: 0,bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        color.setFill(); NSBezierPath(rect: NSRect(x: 0,y: 0,width: 320,height: 180)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let url = folder.appendingPathComponent(name)
        try bitmap.representation(using: .png,properties: [:])!.write(to: url)
        return url
    }
    @MainActor
    func testStillImageCompositionExportAndReimport() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try makeImage(in: folder)
        let library = MediaLibrary()
        let media = try await library.analyze(url)
        XCTAssertEqual(media.kind,.image); XCTAssertEqual(media.width,320)
        let thumbnail = try await library.thumbnail(media)
        XCTAssertNotNil(thumbnail)
        var project = RenderProject(); project.settings.width = 320; project.settings.height = 180
        project.assets = [media]
        var clip = TimelineClip(assetID: media.id,name: media.name,start: 15,duration: 30)
        clip.effects = [Effect(kind: .saturation)]
        project.tracks[0].clips = [clip]
        var configuration = ExportConfiguration(); configuration.width = 320; configuration.height = 180
        let output = folder.appendingPathComponent("out.mp4")
        let service = ExportService()
        try await service.export(project: project,configuration: configuration,to: output)
        XCTAssertEqual(service.progress,1)
        let result = try await library.analyze(output)
        XCTAssertEqual(result.kind,.video)
        XCTAssertEqual(result.width,320); XCTAssertEqual(result.height,180)
        XCTAssertEqual(result.duration,1.5,accuracy: 0.08)
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: output))
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        let black = try await generator.image(at: CMTime(seconds: 0.1,preferredTimescale: 600)).image
        let red = try await generator.image(at: CMTime(seconds: 0.8,preferredTimescale: 600)).image
        let blackPixel = pixel(black); let redPixel = pixel(red)
        XCTAssertLessThan(blackPixel[0],20)
        XCTAssertGreaterThan(redPixel[0],180); XCTAssertLessThan(redPixel[1],40)
        // Round-trip a real encoded video through source-track decoding, speed and the compositor.
        var videoProject = RenderProject(); videoProject.settings = project.settings; videoProject.assets = [result]
        var videoClip = TimelineClip(assetID: result.id,name: "Encoded",start: 0,duration: 15)
        videoClip.sourceIn = 0.5; videoClip.speed = 2
        videoProject.tracks[0].clips = [videoClip]
        let roundtrip = folder.appendingPathComponent("roundtrip.mp4")
        try await service.export(project: videoProject,configuration: configuration,to: roundtrip)
        let roundtripMedia = try await library.analyze(roundtrip)
        XCTAssertEqual(roundtripMedia.duration,0.5,accuracy: 0.08)
        do { try await service.export(project: project,configuration: configuration,to: output); XCTFail("Existing output overwritten") } catch {}
    }
    @MainActor
    func testLayerOrderOpacityAndEffectParity() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = MediaLibrary()
        let red = try await library.analyze(makeImage(in: folder))
        let blue = try await library.analyze(makeImage(in: folder,name: "blue.png",color: .blue))
        var project = RenderProject(); project.settings.width = 320; project.settings.height = 180
        project.assets = [red,blue]
        var top = TimelineClip(assetID: red.id,name: "Red",start: 0,duration: 15)
        top.properties.opacity = 0.5
        project.tracks[0].clips = [top]
        var lower = TimelineTrack(name: "Lower",kind: .video)
        lower.clips = [TimelineClip(assetID: blue.id,name: "Blue",start: 0,duration: 15)]
        project.tracks.insert(lower,at: 1)
        let prepared = try await CompositionBuilder().build(project)
        let generator = AVAssetImageGenerator(asset: prepared.composition)
        generator.videoComposition = prepared.videoComposition
        let preview = try await generator.image(at: CMTime(seconds: 0.2,preferredTimescale: 600)).image
        var config = ExportConfiguration(); config.width = 320; config.height = 180
        let output = folder.appendingPathComponent("mix.mp4")
        try await ExportService().export(project: project,configuration: config,to: output)
        let encoded = try await AVAssetImageGenerator(asset: AVURLAsset(url: output)).image(at: CMTime(seconds: 0.2,preferredTimescale: 600)).image
        let a = pixel(preview), b = pixel(encoded)
        XCTAssertGreaterThan(a[0],80); XCTAssertGreaterThan(a[2],80); XCTAssertLessThan(a[1],40)
        for i in 0..<3 { XCTAssertEqual(Double(a[i]),Double(b[i]),accuracy: 15) }
    }
    func testMissingAndCorruptMediaFailGracefully() async throws {
        let library = MediaLibrary()
        do { _ = try await library.analyze(URL(fileURLWithPath: "/nonexistent/Render-test.mov")); XCTFail("Missing file accepted") } catch {}
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not a movie".utf8).write(to: url)
        do { _ = try await library.analyze(url); XCTFail("Corrupt media accepted") } catch {}
    }
    private func pixel(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0,count: 4)
        bytes.withUnsafeMutableBytes { ptr in
            let context = CGContext(data: ptr.baseAddress,width: 1,height: 1,bitsPerComponent: 8,bytesPerRow: 4,space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image,in: CGRect(x: 0,y: 0,width: 1,height: 1))
        }
        return bytes
    }
}
