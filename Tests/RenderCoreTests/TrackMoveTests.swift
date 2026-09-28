import XCTest
@testable import RenderCore

final class TrackMoveTests: XCTestCase {
    func fixture() -> RenderProject {
        var p = RenderProject()
        let media = MediaAsset(url: URL(fileURLWithPath: "/source.mov"),kind: .video,duration: 60,audioChannels: 2)
        p.assets = [media]
        p.tracks = (0..<4).map { TimelineTrack(name: "V\($0)",kind: .video) } + [TimelineTrack(name: "Audio",kind: .audio)]
        p.tracks[0].clips = [TimelineClip(assetID: media.id,name: "A",start: 30,duration: 60)]
        p.tracks[1].clips = [TimelineClip(assetID: media.id,name: "B",start: 120,duration: 60)]
        return p
    }
    func testAtomicGroupMoveRetainsSourceAndRelativeTrackSpacing() throws {
        var p = fixture(); p.tracks[0].clips[0].sourceIn = 2; p.tracks[0].clips[0].animationOffset = 30
        let ids = Set(p.tracks.flatMap(\.clips).map(\.id))
        let tx = try ProjectTransaction(.moveAcrossTracks(clips: ids,delta: 15,trackOffset: 1),project: p)
        XCTAssertEqual(tx.before,p); XCTAssertTrue(tx.after.tracks[0].clips.isEmpty)
        XCTAssertEqual(tx.after.tracks[1].clips[0].start,45); XCTAssertEqual(tx.after.tracks[2].clips[0].start,135)
        XCTAssertEqual(tx.after.tracks[1].clips[0].sourceIn,2); XCTAssertEqual(tx.after.tracks[1].clips[0].animationOffset,30)
        XCTAssertEqual(try JSONDecoder().decode(RenderProject.self,from: JSONEncoder().encode(tx.after)),tx.after)
    }
    func testInvalidDestinationsDoNotChangeTheProject() throws {
        let original = fixture(), id = original.tracks[0].clips[0].id
        for (delta,offset) in [(Int64(0),-1),(0,4),(-31,1),(100_000_000,1),(0,Int.max),(0,Int.min)] {
            XCTAssertThrowsError(try TimelineCommand.moveAcrossTracks(clips: [id],delta: delta,trackOffset: offset).applying(to: original))
        }
        var locked = original; locked.tracks[2].locked = true
        XCTAssertThrowsError(try TimelineCommand.moveAcrossTracks(clips: [id],delta: 0,trackOffset: 2).applying(to: locked))
        locked = original; locked.tracks[0].locked = true
        XCTAssertThrowsError(try TimelineCommand.moveAcrossTracks(clips: [id],delta: 0,trackOffset: 2).applying(to: locked))
        XCTAssertThrowsError(try TimelineCommand.moveAcrossTracks(clips: [id],delta: 100,trackOffset: 1).applying(to: original))
        XCTAssertEqual(original.tracks[0].clips[0].start,30)
    }
    func testConnectedChildrenFollowTimeWhenAnchorLeavesStoryline() throws {
        var p = fixture(); p.tracks[0].clips[0].start = 0
        let anchor = p.tracks[0].clips[0].id, child = p.tracks[1].clips[0].id
        p.storyline = StorylineSettings(enabled: true,trackID: p.tracks[0].id)
        p.tracks[1].clips[0].connection = ClipConnection(anchor: anchor,offset: 120)
        let moved = try TimelineCommand.moveAcrossTracks(clips: [anchor],delta: 15,trackOffset: 2).applying(to: p)
        XCTAssertEqual(moved.clip(child)?.start,135); XCTAssertNil(moved.clip(child)?.connection)
        XCTAssertEqual(moved.tracks[2].clips[0].start,15)
        p.tracks[1].locked = true
        XCTAssertThrowsError(try TimelineCommand.moveAcrossTracks(clips: [anchor],delta: 15,trackOffset: 2).applying(to: p))
    }
    func testMovingOntoStorylinePacksAndClearsConnection() throws {
        var p = fixture(); p.tracks[0].clips[0].start = 0
        p.storyline = StorylineSettings(enabled: true,trackID: p.tracks[0].id)
        let child = p.tracks[1].clips[0].id
        let moved = try TimelineCommand.moveAcrossTracks(clips: [child],delta: 0,trackOffset: -1).applying(to: p)
        XCTAssertEqual(moved.clip(child)?.start,60); XCTAssertTrue(moved.tracks[1].clips.isEmpty)
    }
}
