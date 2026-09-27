import XCTest
@testable import RenderCore

final class MediaVariantTests: XCTestCase {
    func testResolutionFallbackOfflineAndChangedSource() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.mov"), proxy = folder.appendingPathComponent("proxy.mov")
        try Data("original".utf8).write(to: source); try Data("proxy".utf8).write(to: proxy)
        var media = MediaAsset(url: source,kind: .video,duration: 2)
        media.variants = [MediaVariant(mode: .proxy,url: proxy,source: try SourceFingerprint(url: source))]
        XCTAssertEqual(MediaResolver.url(for: media,mode: .proxy),proxy)
        XCTAssertEqual(MediaResolver.url(for: media,mode: .original),source)
        XCTAssertEqual(MediaResolver.url(for: media,mode: .optimized),source)
        try FileManager.default.removeItem(at: source)
        XCTAssertEqual(MediaResolver.url(for: media,mode: .proxy),proxy)
        try Data("changed original file".utf8).write(to: source)
        XCTAssertEqual(MediaResolver.url(for: media,mode: .proxy),source)
        try FileManager.default.removeItem(at: proxy)
        XCTAssertEqual(MediaResolver.url(for: media,mode: .proxy),source)
    }
    func testVariantAttachmentUndoRelinkAndRoundTrip() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data([1,2,3]).write(to: file)
        var project = TimelineTests().fixture(); project.assets[0].url = file
        let id = project.assets[0].id
        let variant = MediaVariant(mode: .proxy,url: file.deletingLastPathComponent().appendingPathComponent("proxy.mov"),source: try SourceFingerprint(url: file))
        let transaction = try ProjectTransaction(.mediaVariant(asset: id,variant),project: project)
        XCTAssertEqual(transaction.before,project)
        XCTAssertEqual(transaction.after.assets[0].variants,[variant])
        let read = try JSONDecoder().decode(RenderProject.self,from: JSONEncoder().encode(transaction.after))
        XCTAssertEqual(read,transaction.after)
        let relinked = try TimelineCommand.relink(asset: id,URL(fileURLWithPath: "/tmp/relinked.mov")).applying(to: read)
        XCTAssertNil(relinked.assets[0].variants)
        XCTAssertThrowsError(try TimelineCommand.mediaVariant(asset: id,variant).applying(to: relinked))
    }
    func testInvalidVariantModesAndDuplicateRepresentationsAreRejected() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data([1]).write(to: file)
        var project = TimelineTests().fixture()
        let variant = MediaVariant(mode: .original,url: file,source: try SourceFingerprint(url: file))
        project.assets[0].variants = [variant]
        XCTAssertThrowsError(try project.validate())
    }
}
