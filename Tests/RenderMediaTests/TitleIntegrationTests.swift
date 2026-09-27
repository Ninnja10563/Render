import XCTest
import AVFoundation
import AppKit
import RenderCore
@testable import RenderMedia

extension MediaIntegrationTests {
    @MainActor
    func testGeneratedTitleExportAndResolutionIndependentPosition() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var title = TitleContent(text: "Render"); title.fontSize = 30; title.background = RGBAColor(1,0,0)
        title.padding = 5; title.shadow.alpha = 0
        var project = RenderProject(); project.settings.width = 640; project.settings.height = 360
        project = try TimelineCommand.addTitle(title,at: 0,duration: 6).applying(to: project)
        project.tracks[0].clips[0].properties.x = 120
        var config = ExportConfiguration(); config.width = 320; config.height = 180
        let output = folder.appendingPathComponent("title.mp4")
        try await ExportService().export(project: project,configuration: config,to: output)
        let encoded = try await AVAssetImageGenerator(asset: AVURLAsset(url: output)).image(at: CMTime(value: 1,timescale: 30)).image
        // The title center moves 60 output pixels, preserving the 120-pixel sequence offset.
        let center = pixel(try XCTUnwrap(encoded.cropping(to: CGRect(x: 210,y: 90,width: 8,height: 8))))
        let wrongPosition = pixel(try XCTUnwrap(encoded.cropping(to: CGRect(x: 280,y: 90,width: 8,height: 8))))
        XCTAssertGreaterThan(center[0],180); XCTAssertLessThan(wrongPosition[0],30)
        let built = try await CompositionBuilder().build(project,outputSize: CGSize(width: 320,height: 180))
        let generator = AVAssetImageGenerator(asset: built.composition); generator.videoComposition = built.videoComposition
        let preview = try await generator.image(at: CMTime(value: 1,timescale: 30)).image
        // Compare a region mean, not a single resampled pixel on a glyph edge: H.264 chroma
        // subsampling legitimately changes individual red/white edge pixels.
        func mean(_ image: CGImage) -> [Double] {
            var bytes = [UInt8](repeating: 0,count: image.width * image.height * 4)
            bytes.withUnsafeMutableBytes { data in
                let context = CGContext(data: data.baseAddress,width: image.width,height: image.height,bitsPerComponent: 8,bytesPerRow: image.width * 4,space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(image,in: CGRect(x: 0,y: 0,width: image.width,height: image.height))
            }
            return (0..<3).map { channel in stride(from: channel,to: bytes.count,by: 4).reduce(0.0) { $0 + Double(bytes[$1]) } / Double(image.width * image.height) }
        }
        let region = CGRect(x: 205,y: 85,width: 24,height: 16)
        let a = mean(try XCTUnwrap(preview.cropping(to: region)))
        let b = mean(try XCTUnwrap(encoded.cropping(to: region)))
        for channel in 0..<3 { XCTAssertEqual(a[channel],b[channel],accuracy: 15) }
    }
}
