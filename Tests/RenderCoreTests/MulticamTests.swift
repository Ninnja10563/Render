import XCTest
@testable import RenderCore

final class MulticamTests: XCTestCase {
    func fixture() throws -> (RenderProject,MulticamSource) {
        var project = TimelineTests().fixture(); project.tracks[0].clips.removeLast()
        var other = project.assets[0]; other.id = UUID(); other.url = URL(fileURLWithPath: "/tmp/camera-b.mov")
        project.assets.append(other); project.tracks[0].clips[0].sourceIn = 5
        let source = MulticamSource(name: "Interview",angles: [CameraAngle(name: "Wide",assetID: project.assets[0].id),CameraAngle(name: "Close",assetID: other.id,offset: 2)])
        project = try TimelineCommand.makeMulticam(clip: project.tracks[0].clips[0].id,source).applying(to: project)
        return (project,source)
    }
    func testCutUsesSourceOffsetAndPreservesAnimationAndUndo() throws {
        let (project,source) = try fixture(); let original = project.tracks[0].clips[0]
        let transaction = try ProjectTransaction(.switchAngle(clip: original.id,angle: source.angles[1].id,at: 90),project: project)
        let clips = transaction.after.tracks[0].clips.sorted { $0.start < $1.start }
        XCTAssertEqual(clips.map(\.duration),[90,210]); XCTAssertEqual(clips[0].assetID,original.assetID)
        XCTAssertEqual(clips[1].sourceIn,10); XCTAssertEqual(clips[1].animationOffset,90)
        XCTAssertEqual(clips[1].assetID,source.angles[1].assetID); XCTAssertEqual(transaction.before,project)
        let restored = try TimelineCommand.switchAngle(clip: clips[1].id,angle: source.angles[0].id,at: nil).applying(to: transaction.after)
        XCTAssertEqual(restored.clip(clips[1].id)?.sourceIn,8)
        XCTAssertEqual(try JSONDecoder().decode(RenderProject.self,from: JSONEncoder().encode(restored)),restored)
    }
    func testUnavailableRangeLockedTrackAndBadMembershipAreRejected() throws {
        var (p,source) = try fixture(); let id = p.tracks[0].clips[0].id
        p.assets[1].duration = 6
        XCTAssertThrowsError(try TimelineCommand.switchAngle(clip: id,angle: source.angles[1].id,at: nil).applying(to: p))
        p.assets[1].duration = 60; p.tracks[0].locked = true
        XCTAssertThrowsError(try TimelineCommand.switchAngle(clip: id,angle: source.angles[1].id,at: 30).applying(to: p))
        p.tracks[0].locked = false; p.tracks[0].clips[0].multicam?.angleID = UUID()
        XCTAssertThrowsError(try p.validate())
        source.angles[1].offset = .nan
        XCTAssertThrowsError(try source.validate(assets: Dictionary(uniqueKeysWithValues: p.assets.map { ($0.id,$0) })))
    }
    func testSpeedAndLateRecordingOffsets() throws {
        var (p,source) = try fixture(); let id = p.tracks[0].clips[0].id
        p.tracks[0].clips[0].speed = 2
        let cut = try TimelineCommand.switchAngle(clip: id,angle: source.angles[1].id,at: 90).applying(to: p)
        XCTAssertEqual(cut.tracks[0].clips.last?.sourceIn,13)
        p.multicamSources?[0].angles[1].offset = -10
        XCTAssertThrowsError(try TimelineCommand.switchAngle(clip: id,angle: source.angles[1].id,at: nil).applying(to: p))
    }
    func testDetachedAudioIsIndependentOfCameraMembership() throws {
        var (p,_) = try fixture(); p.assets[0].audioChannels = 2
        let edited = try TimelineCommand.detachAudio(clip: p.tracks[0].clips[0].id).applying(to: p)
        XCTAssertNil(edited.tracks.last?.clips.first?.multicam)
        XCTAssertNotNil(edited.tracks[0].clips[0].multicam)
    }
}
