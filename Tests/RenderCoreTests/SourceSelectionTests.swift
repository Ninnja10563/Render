import XCTest
@testable import RenderCore

final class SourceSelectionTests: XCTestCase {
    func fixture() -> RenderProject {
        var project = RenderProject()
        let media = MediaAsset(url: URL(fileURLWithPath: "/source.mov"),kind: .video,duration: 20)
        project.assets = [media]
        project.tracks[0].clips = [TimelineClip(assetID: media.id,name: "Existing",start: 0,duration: 300)]
        return project
    }
    func testMarksDoNotChangeExistingClipsAndDriveAllThreeEditingModes() throws {
        let original = fixture(), id = original.assets[0].id, track = original.tracks[0].id
        let marked = try TimelineCommand.sourceSelection(asset: id,SourceSelection(start: 2,end: 3.5)).applying(to: original)
        XCTAssertEqual(marked.tracks,original.tracks)
        XCTAssertTrue(marked.assets[0].hasSamePlaybackSource(as: original.assets[0]))
        for command in [TimelineCommand.append(asset: id,track: track,at: 300),.insert(asset: id,track: track,at: 90),.overwrite(asset: id,track: track,at: 90)] {
            let tx = try ProjectTransaction(command,project: marked)
            let inserted = try XCTUnwrap(tx.after.tracks[0].clips.first { $0.name != "Existing" })
            XCTAssertEqual(inserted.sourceIn,2); XCTAssertEqual(inserted.duration,45); XCTAssertEqual(tx.before,marked)
        }
        let inserted = try TimelineCommand.insert(asset: id,track: track,at: 90).applying(to: marked)
        XCTAssertEqual(inserted.duration,345)
        XCTAssertEqual(inserted.tracks[0].clips.first(where: { $0.start == 135 && $0.name == "Existing" })?.sourceIn,3)
        let overwritten = try TimelineCommand.overwrite(asset: id,track: track,at: 90).applying(to: marked)
        XCTAssertEqual(overwritten.duration,300)
        XCTAssertEqual(overwritten.tracks[0].clips.first(where: { $0.start == 135 && $0.name == "Existing" })?.sourceIn,4.5)
    }
    func testRangeBoundsAndFractionalRateFrameCounts() throws {
        let p = fixture(),id = p.assets[0].id
        for range in [SourceSelection(start: -1,end: 2),.init(start: 1,end: 1),.init(start: 0,end: 21),.init(start: .nan,end: 2),.init(start: 0,end: .infinity)] {
            XCTAssertThrowsError(try TimelineCommand.sourceSelection(asset: id,range).applying(to: p))
        }
        let rate = FrameRate(24000,1001)
        XCTAssertEqual(try SourceSelection(start: rate.seconds(20),end: rate.seconds(100)).clipFrames(at: rate),80)
        XCTAssertThrowsError(try SourceSelection(start: 0,end: 0.001).clipFrames(at: rate))
        let marked = try TimelineCommand.sourceSelection(asset: id,.init(start: 0,end: 0.001)).applying(to: p)
        XCTAssertThrowsError(try TimelineCommand.append(asset: id,track: p.tracks[0].id,at: 300).applying(to: marked))
        XCTAssertEqual(try TimelineCommand.sourceSelection(asset: id,nil).applying(to: marked),p)
    }
    func testSavedMarksAndEarlierSchemaMigration() async throws {
        var p = fixture(); p.assets[0].selection = SourceSelection(start: 3,end: 5)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ProjectStore(); try await store.save(p,to: url)
        let loaded = try await store.load(url); XCTAssertEqual(loaded,p)
        p.assets[0].selection = nil
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as! [String: Any]
        object["schemaVersion"] = 11
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        let migrated = try await store.load(url); XCTAssertEqual(migrated,p)
    }
}
