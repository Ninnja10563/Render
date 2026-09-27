import XCTest
@testable import RenderCore

final class MagneticEditingTests: XCTestCase {
    func fixture() throws -> RenderProject {
        var project = TimelineTests().fixture()
        project = try TimelineCommand.storyline(enabled: true,track: project.tracks[0].id).applying(to: project)
        var track = TimelineTrack(name: "Connected",kind: .video)
        var child = TimelineClip(assetID: project.assets[0].id,name: "Connected",start: 320,duration: 30)
        child.connection = ClipConnection(anchor: project.tracks[0].clips[1].id,offset: 20)
        track.clips = [child]; project.tracks.insert(track,at: 1)
        try project.validate(); return project
    }
    func testReorderingInBothDirectionsCarriesConnections() throws {
        let original = try fixture(); let id = original.tracks[0].clips[1].id
        let before = try TimelineCommand.move(clips: [id],delta: -300).applying(to: original)
        XCTAssertEqual(before.tracks[0].clips.map(\.id),[id,original.tracks[0].clips[0].id])
        XCTAssertEqual(before.tracks[1].clips[0].start,20)
        let after = try TimelineCommand.move(clips: [id],delta: 300).applying(to: before)
        XCTAssertEqual(after,original)
    }
    func testModeCompactsGapsButKeepsExplicitGapClips() throws {
        var project = TimelineTests().fixture(); let track = project.tracks[0].id
        project.tracks[0].clips[1].start = 450
        project = try TimelineCommand.storyline(enabled: true,track: track).applying(to: project)
        XCTAssertEqual(project.tracks[0].clips[1].start,300)
        project = try TimelineCommand.gap(track: track,at: 300,duration: 60).applying(to: project)
        XCTAssertEqual(project.tracks[0].clips.map(\.start),[0,300,360])
        XCTAssertEqual(project.tracks[0].clips[1].isGap,true)
        XCTAssertEqual(project.duration,660)
    }
    func testDeleteAnchorDeletesConnectedClipsAndUndoRetainsEverything() throws {
        let project = try fixture()
        let command = TimelineCommand.delete(clips: [project.tracks[0].clips[1].id],ripple: false)
        let transaction = try ProjectTransaction(command,project: project)
        XCTAssertEqual(transaction.after.tracks[0].clips.count,1)
        XCTAssertTrue(transaction.after.tracks[1].clips.isEmpty)
        XCTAssertEqual(transaction.before,project)
    }
    func testLockedConnectionBlocksAnchorMovementAtomically() throws {
        var project = try fixture(); project.tracks[1].locked = true
        XCTAssertThrowsError(try TimelineCommand.move(clips: [project.tracks[0].clips[1].id],delta: -300).applying(to: project))
        XCTAssertEqual(project.tracks[1].clips[0].start,320)
    }
    func testSplitReanchorsLaterConnectionsAndGapInsertionRipplesThem() throws {
        var project = try fixture()
        let anchor = project.tracks[0].clips[1].id
        project.tracks[1].clips[0].start = 400
        project.tracks[1].clips[0].connection?.offset = 100
        project = try TimelineCommand.gap(track: project.tracks[0].id,at: 350,duration: 60).applying(to: project)
        let child = project.tracks[1].clips[0]
        XCTAssertEqual(child.start,460)
        XCTAssertNotEqual(child.connection?.anchor,anchor)
        let right = try XCTUnwrap(project.clip(child.connection!.anchor))
        XCTAssertEqual(right.start,410); XCTAssertEqual(child.connection?.offset,50)
    }
    func testLeadingRippleTrimPreservesConnectionToContent() throws {
        let project = try fixture()
        let anchor = project.tracks[0].clips[1].id
        let edited = try TimelineCommand.rippleTrim(clip: anchor,edge: .leading,to: 310).applying(to: project)
        XCTAssertEqual(edited.tracks[1].clips[0].start,310)
        XCTAssertEqual(edited.tracks[1].clips[0].connection?.offset,10)
    }
    func testMultitrackPasteConnectsToCopiedAnchor() throws {
        let project = try fixture()
        let lanes = [ClipboardLane(trackID: project.tracks[0].id,clips: project.tracks[0].clips),ClipboardLane(trackID: project.tracks[1].id,clips: project.tracks[1].clips)]
        let pasted = try TimelineCommand.pasteLanes(lanes,at: 600).applying(to: project)
        let child = try XCTUnwrap(pasted.tracks[1].clips.first { $0.start == 920 })
        let anchor = try XCTUnwrap(pasted.clip(child.connection!.anchor))
        XCTAssertEqual(anchor.start,900)
        XCTAssertNotEqual(anchor.id,project.tracks[0].clips[1].id)
        XCTAssertEqual(child.connection?.offset,20)
    }
    func testTraditionalModeKeepsGapsAndCanDisconnect() throws {
        var project = try fixture()
        project = try TimelineCommand.storyline(enabled: false,track: project.tracks[0].id).applying(to: project)
        let child = project.tracks[1].clips[0].id
        project = try TimelineCommand.connection(clip: child,anchor: nil).applying(to: project)
        project = try TimelineCommand.move(clips: [project.tracks[0].clips[1].id],delta: 60).applying(to: project)
        XCTAssertEqual(project.tracks[0].clips[1].start,360)
        XCTAssertEqual(project.tracks[1].clips[0].start,320)
        XCTAssertNil(project.tracks[1].clips[0].connection)
        XCTAssertEqual(try JSONDecoder().decode(RenderProject.self,from: JSONEncoder().encode(project)),project)
    }
}
