import XCTest
@testable import RenderCore

final class TimelineTests: XCTestCase {
    func fixture() -> RenderProject {
        var p = RenderProject()
        let asset = MediaAsset(url: URL(fileURLWithPath: "/tmp/source.mov"), kind: .video, duration: 60)
        p.assets = [asset]
        p.tracks[0].clips = [TimelineClip(assetID: asset.id, name: "A", start: 0, duration: 300), TimelineClip(assetID: asset.id, name: "B", start: 300, duration: 300)]
        return p
    }
    func testSplitPreservesSourceAndAnimationTime() throws {
        var p = fixture(); p.tracks[0].clips[0].speed = 2
        let id = p.tracks[0].clips[0].id
        let after = try TimelineCommand.split(clips: [id], at: 120).applying(to: p)
        let clips = after.tracks[0].clips.sorted { $0.start < $1.start }
        XCTAssertEqual(clips.map(\.duration), [120,180,300])
        XCTAssertEqual(clips[1].sourceIn, 8)
        XCTAssertEqual(clips[1].animationOffset, 120)
        XCTAssertEqual(clips[0].id, id)
        XCTAssertNotEqual(clips[1].id, id)
        XCTAssertEqual(after.duration, p.duration)
    }
    func testSplitAtBoundaryIsNoOp() throws {
        let p = fixture()
        XCTAssertEqual(try TimelineCommand.split(clips: [p.tracks[0].clips[0].id], at: 0).applying(to: p), p)
    }
    func testLeadingTrimChangesSourceIn() throws {
        let p = fixture()
        let after = try TimelineCommand.trim(clip: p.tracks[0].clips[0].id, edge: .leading, to: 30).applying(to: p)
        XCTAssertEqual(after.tracks[0].clips[0].sourceIn, 1)
        XCTAssertEqual(after.tracks[0].clips[0].duration, 270)
        XCTAssertEqual(after.tracks[0].clips[0].end, 300)
    }
    func testInvalidTrimIsAtomic() {
        let p = fixture()
        XCTAssertThrowsError(try TimelineCommand.trim(clip: p.tracks[0].clips[0].id, edge: .trailing, to: 0).applying(to: p))
        XCTAssertEqual(p.tracks[0].clips[0].duration, 300)
    }
    func testOverlapRejected() {
        let p = fixture()
        XCTAssertThrowsError(try TimelineCommand.move(clips: [p.tracks[0].clips[1].id], delta: -10).applying(to: p))
    }
    func testGroupMovePreservesSpacing() throws {
        let p = fixture()
        let after = try TimelineCommand.move(clips: Set(p.tracks[0].clips.map(\.id)), delta: 30).applying(to: p)
        XCTAssertEqual(after.tracks[0].clips.map(\.start), [30,330])
    }
    func testRippleDeleteClosesSelectedDurationOnly() throws {
        var p = fixture(); p.tracks[0].clips[1].start = 330
        let after = try TimelineCommand.delete(clips: [p.tracks[0].clips[0].id], ripple: true).applying(to: p)
        XCTAssertEqual(after.tracks[0].clips[0].start, 30)
    }
    func testDeleteLeavesGap() throws {
        let p = fixture()
        let after = try TimelineCommand.delete(clips: [p.tracks[0].clips[0].id], ripple: false).applying(to: p)
        XCTAssertEqual(after.tracks[0].clips[0].start, 300)
    }
    func testInsertSplitsAndRipples() throws {
        let p = fixture()
        let after = try TimelineCommand.insert(asset: p.assets[0].id, track: p.tracks[0].id, at: 120).applying(to: p)
        let clips = after.tracks[0].clips.sorted { $0.start < $1.start }
        XCTAssertEqual(clips.map(\.start), [0,120,1920,2100])
        XCTAssertEqual(clips[2].sourceIn, 4)
        XCTAssertEqual(after.duration, 2400)
    }
    func testLockedTrackRejectsEveryClipMutation() {
        var p = fixture(); p.tracks[0].locked = true
        let id = p.tracks[0].clips[0].id
        let commands: [TimelineCommand] = [.delete(clips: [id], ripple: true), .move(clips: [id], delta: 30), .split(clips: [id], at: 30), .trim(clip: id, edge: .leading, to: 30), .speed(clip: id, 2), .properties(clip: id, ClipProperties()), .effects(clip: id, [])]
        for command in commands { XCTAssertThrowsError(try command.applying(to: p)) }
    }
    func testSpeedPreservesSourceRange() throws {
        let p = fixture()
        let after = try TimelineCommand.speed(clip: p.tracks[0].clips[0].id, 2).applying(to: p)
        XCTAssertEqual(after.tracks[0].clips[0].duration, 150)
        XCTAssertEqual(after.tracks[0].clips[0].speed, 2)
    }
    func testTransactionHasExactUndoAndRedoSnapshots() throws {
        let p = fixture()
        let transaction = try ProjectTransaction(.split(clips: [p.tracks[0].clips[0].id], at: 100), project: p)
        var current = transaction.after
        current = transaction.before
        XCTAssertEqual(current, p)
        current = transaction.after
        XCTAssertEqual(current.tracks[0].clips.count, 3)
    }
    func testPasteGeneratesNewIdentity() throws {
        let p = fixture()
        let after = try TimelineCommand.paste(clips: [p.tracks[0].clips[0]], track: p.tracks[0].id, at: 600).applying(to: p)
        XCTAssertEqual(after.tracks[0].clips[2].start, 600)
        XCTAssertNotEqual(after.tracks[0].clips[2].id, p.tracks[0].clips[0].id)
    }
    func testWrongTrackKindRejected() {
        let p = fixture()
        XCTAssertThrowsError(try TimelineCommand.moveToTrack(clip: p.tracks[0].clips[0].id, track: p.tracks[1].id, at: 0).applying(to: p))
    }
    func testSourceOverrunRejected() {
        let p = fixture()
        XCTAssertThrowsError(try TimelineCommand.trim(clip: p.tracks[0].clips[1].id, edge: .trailing, to: 2200).applying(to: p))
    }
    func testSnapUsesPixelDerivedThreshold() {
        XCTAssertEqual(TimelineSnap.frame(99, targets: [0,100,200], threshold: 2), 100)
        XCTAssertEqual(TimelineSnap.frame(97, targets: [0,100,200], threshold: 2), 97)
    }
}

extension TimelineTests {
    func testExtremeEditPositionsAreRejectedWithoutIntegerOverflow() {
        let p = fixture(); let id = p.tracks[0].clips[0].id
        for frame in [Int64.min, Int64.max, -1] {
            XCTAssertThrowsError(try TimelineCommand.trim(clip: id,edge: .leading,to: frame).applying(to: p))
            XCTAssertThrowsError(try TimelineCommand.split(clips: [id],at: frame).applying(to: p))
            XCTAssertThrowsError(try TimelineCommand.insert(asset: p.assets[0].id,track: p.tracks[0].id,at: frame).applying(to: p))
        }
    }
}
