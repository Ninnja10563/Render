import XCTest
@testable import RenderCore

final class AnimationEditingTests: XCTestCase {
    func testValueChangePreservesIdentityAndInterpolation() throws {
        let key = Keyframe(frame: 10,value: 0.4,interpolation: .easeInOut)
        let result = try AnimationEdit.set(frame: 10,value: 0.8).applying(to: AnimationCurve(keys: [key]))
        XCTAssertEqual(result.keys.count,1)
        XCTAssertEqual(result.keys[0].id,key.id)
        XCTAssertEqual(result.keys[0].interpolation,.easeInOut)
        XCTAssertEqual(result.keys[0].value,0.8)
    }
    func testMoveSortsAndRejectsCollisionsWithoutLosingKeys() throws {
        let a = Keyframe(frame: 10,value: 0), b = Keyframe(frame: 20,value: 1)
        let original = AnimationCurve(keys: [a,b])
        let moved = try AnimationEdit.move(key: a.id,to: 30).applying(to: original)
        XCTAssertEqual(moved.keys.map(\.id),[b.id,a.id])
        XCTAssertThrowsError(try AnimationEdit.move(key: a.id,to: 20).applying(to: original))
        XCTAssertThrowsError(try AnimationEdit.move(key: a.id,to: -1).applying(to: original))
        XCTAssertThrowsError(try AnimationEdit.move(key: UUID(),to: 15).applying(to: original))
        XCTAssertEqual(original.keys,[a,b])
    }
    func testPastePreservesSpacingAndCurveWithNewIdentity() throws {
        let a = Keyframe(frame: 50,value: 0,interpolation: .hold), b = Keyframe(frame: 80,value: 1,interpolation: .easeOut)
        let destination = AnimationCurve(keys: [Keyframe(frame: 10,value: 0.5),Keyframe(frame: 100,value: 0.2)])
        let pasted = try AnimationEdit.paste([b,a],at: 10).applying(to: destination)
        XCTAssertEqual(pasted.keys.map(\.frame),[10,40,100])
        XCTAssertEqual(pasted.keys.map(\.value),[0,1,0.2])
        XCTAssertEqual(pasted.keys[0].interpolation,.hold)
        XCTAssertEqual(pasted.keys[1].interpolation,.easeOut)
        XCTAssertNotEqual(pasted.keys[0].id,a.id)
        XCTAssertThrowsError(try AnimationEdit.paste([a,b],at: 199_999_999).applying(to: destination))
        XCTAssertThrowsError(try AnimationEdit.paste([Keyframe(frame: Int64.min,value: 1)],at: 1).applying(to: destination))
    }
    func testEffectAnimationTransactionValidationAndUndoSnapshot() throws {
        var project = TimelineTests().fixture()
        let effect = Effect(kind: .exposure)
        project.tracks[0].clips[0].effects = [effect]
        let id = project.tracks[0].clips[0].id
        let command = TimelineCommand.animation(clip: id,target: .effect(effect.id),edit: .set(frame: 20,value: 2))
        let transaction = try ProjectTransaction(command,project: project)
        XCTAssertEqual(transaction.before,project)
        XCTAssertEqual(transaction.after.clip(id)?.effects[0].animation.keys.first?.value,2)
        XCTAssertThrowsError(try TimelineCommand.animation(clip: id,target: .effect(effect.id),edit: .set(frame: 30,value: 5)).applying(to: project))
        project.tracks[0].locked = true
        XCTAssertThrowsError(try command.applying(to: project))
    }
    func testTrimSplitAndSerializationRetainAnimationPhase() throws {
        var project = TimelineTests().fixture()
        let id = project.tracks[0].clips[0].id
        project = try TimelineCommand.animation(clip: id,target: .property("opacity"),edit: .paste([Keyframe(frame: 0,value: 0,interpolation: .easeInOut),Keyframe(frame: 100,value: 1)],at: 0)).applying(to: project)
        project = try TimelineCommand.trim(clip: id,edge: .leading,to: 25).applying(to: project)
        project = try TimelineCommand.split(clips: [id],at: 50).applying(to: project)
        let right = try XCTUnwrap(project.tracks[0].clips.first { $0.start == 50 })
        XCTAssertEqual(right.animationOffset,50)
        XCTAssertEqual(right.properties.value("opacity",at: Double(right.animationOffset)),0.5,accuracy: 0.0001)
        let decoded = try JSONDecoder().decode(RenderProject.self,from: JSONEncoder().encode(project))
        XCTAssertEqual(decoded,project)
        try decoded.validate()
    }
    func testRemoveAndInterpolationOnlyTouchSelectedKeys() throws {
        let a = Keyframe(frame: 0,value: 0), b = Keyframe(frame: 30,value: 1)
        let changed = try AnimationEdit.interpolation([a.id],.hold).applying(to: AnimationCurve(keys: [a,b]))
        XCTAssertEqual(changed.value(at: 29,fallback: -1),0)
        XCTAssertEqual(changed.keys[1].interpolation,.linear)
        let deleted = try AnimationEdit.remove([a.id]).applying(to: changed)
        XCTAssertEqual(deleted.keys,[b])
    }
}
