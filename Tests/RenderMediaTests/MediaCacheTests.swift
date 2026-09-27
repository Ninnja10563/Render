import XCTest
import AppKit
import AVFoundation
import RenderCore
@testable import RenderMedia

final class MediaCacheTests: XCTestCase {
    func testMetadataAndThumbnailPersistWithFreshImportIdentity() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try MediaIntegrationTests().makeImage(in: folder)
        let cacheFolder = folder.appendingPathComponent("cache")
        let first = MediaLibrary(cacheFolder: cacheFolder)
        let a = try await first.analyze(source)
        let image = try await first.thumbnail(a)
        XCTAssertNotNil(image)
        let files = try FileManager.default.contentsOfDirectory(at: cacheFolder,includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count,2)
        let second = MediaLibrary(cacheFolder: cacheFolder)
        let b = try await second.analyze(source)
        XCTAssertNotEqual(a.id,b.id); XCTAssertEqual(a.width,b.width)
        let cached = try await second.thumbnail(b)
        XCTAssertEqual(cached?.width,image?.width)
        // Corrupt derived data is disposable; a fresh reader regenerates it from the source.
        for file in files { try Data("corrupt".utf8).write(to: file) }
        let fresh = MediaLibrary(cacheFolder: cacheFolder)
        let c = try await fresh.analyze(source)
        XCTAssertEqual(c.width,320)
        let rebuilt = try await fresh.thumbnail(c)
        XCTAssertNotNil(rebuilt)
    }
    func testCacheKeyChangesWithSourceAndOperation() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data([1]).write(to: file)
        let cache = MediaCache()
        let a = try cache.key(file,operation: "a")
        XCTAssertNotEqual(a,try cache.key(file,operation: "b"))
        try Data([1,2]).write(to: file)
        XCTAssertNotEqual(a,try cache.key(file,operation: "a"))
    }
    func testWaveformResolutionIsPartOfCacheKeyAndInvalidBinsFail() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("tone.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000,channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format,frameCapacity: 4800)!
        buffer.frameLength = 4800
        for i in 0..<4800 { buffer.floatChannelData![0][i] = 0.25 }
        do { let file = try AVAudioFile(forWriting: url,settings: format.settings); try file.write(from: buffer) }
        let cacheFolder = folder.appendingPathComponent("cache")
        let library = MediaLibrary(cacheFolder: cacheFolder)
        let media = try await library.analyze(url)
        let short = try await library.waveform(media,bins: 20)
        let long = try await library.waveform(media,bins: 80)
        XCTAssertEqual(short.count,20); XCTAssertEqual(long.count,80)
        let persisted = try await MediaLibrary(cacheFolder: cacheFolder).waveform(media,bins: 80)
        XCTAssertEqual(persisted,long)
        do { _ = try await library.waveform(media,bins: 0); XCTFail("Zero bins accepted") } catch {}
    }
}
