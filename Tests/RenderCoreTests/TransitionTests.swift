import XCTest
@testable import RenderCore

final class TransitionTests: XCTestCase {
    func fixture() -> RenderProject {
        var p = TimelineTests().fixture(); p.tracks[0].clips[1].sourceIn = 10; return p
    }
    func testTransitionUsesHandlesWithoutChangingEditTiming() throws {
        let p = fixture()
        let a = p.tracks[0].clips[0], b = p.tracks[0].clips[1]
        let transition = ClipTransition(rightID: b.id,kind: .crossDissolve,duration: 30)
        let edit = try ProjectTransaction(.transition(clip: a.id,transition),project: p)
        XCTAssertEqual(edit.after.duration,p.duration); XCTAssertEqual(edit.after.clip(b.id)?.start,b.start)
        let window = TransitionWindow(left: a,transition: transition)
        XCTAssertEqual(window.start,285); XCTAssertEqual(window.end,315); XCTAssertEqual(window.progress(at: 300),0.5)
        XCTAssertEqual(edit.before,p)
    }
    func testMissingHandlesWrongNeighborAndExtremeDurationAreRejected() throws {
        var p = fixture(); let a = p.tracks[0].clips[0], b = p.tracks[0].clips[1]
        p.tracks[0].clips[1].sourceIn = 0
        XCTAssertThrowsError(try TimelineCommand.transition(clip: a.id,ClipTransition(rightID: b.id,kind: .wipe,duration: 30)).applying(to: p))
        p.tracks[0].clips[1].sourceIn = 10; p.tracks[0].clips[0].sourceIn = 50
        XCTAssertThrowsError(try TimelineCommand.transition(clip: a.id,ClipTransition(rightID: b.id,kind: .wipe,duration: 30)).applying(to: p))
        p = fixture()
        XCTAssertThrowsError(try TimelineCommand.transition(clip: p.tracks[0].clips[0].id,ClipTransition(rightID: UUID(),kind: .slide,duration: 20)).applying(to: p))
        XCTAssertThrowsError(try TimelineCommand.transition(clip: p.tracks[0].clips[0].id,ClipTransition(rightID: p.tracks[0].clips[1].id,kind: .slide,duration: Int64.max)).applying(to: p))
    }
    func testStructuralEditsRemoveBrokenPairsAndPasteRemapsThem() throws {
        var p = fixture(); let a = p.tracks[0].clips[0], b = p.tracks[0].clips[1]
        p = try TimelineCommand.transition(clip: a.id,ClipTransition(rightID: b.id,kind: .dipToWhite,duration: 20)).applying(to: p)
        let moved = try TimelineCommand.move(clips: [b.id],delta: 30).applying(to: p)
        XCTAssertNil(moved.clip(a.id)?.transition)
        let pasted = try TimelineCommand.pasteLanes([ClipboardLane(trackID: p.tracks[0].id,clips: p.tracks[0].clips)],at: 600).applying(to: p)
        let copy = try XCTUnwrap(pasted.tracks[0].clips.first { $0.start == 600 })
        XCTAssertNotEqual(copy.transition?.rightID,b.id)
        XCTAssertEqual(pasted.clip(copy.transition!.rightID)?.start,900)
        XCTAssertEqual(try JSONDecoder().decode(RenderProject.self,from: JSONEncoder().encode(pasted)),pasted)
    }
    func testAudioCrossfadeEnvelopeAndAutomationMultiply() {
        let base = AudioAutomation.ramps(curve: AnimationCurve(),offset: -15,duration: 330,fallback: 0.8)
        let ramps = AudioAutomation.applyingFades(to: base,duration: 330,fadeIn: 30,fadeOut: 30)
        XCTAssertEqual(ramps.first?.from,0); XCTAssertEqual(ramps.last?.to,0)
        XCTAssertTrue(ramps.contains { $0.from == 0.8 && $0.to == 0.8 })
        XCTAssertEqual(ramps.first?.end,30); XCTAssertEqual(ramps.last?.start,300)
    }
}
