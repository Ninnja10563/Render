import XCTest
@testable import RenderCore

final class ClipGeometryTests: XCTestCase {
    func testGeometryAndCropCurvesRoundTripThroughUndoTransaction() throws {
        let project = TimelineTests().fixture()
        var p = ClipProperties()
        try p.setBaseValue("scaleX",value: 2); try p.setBaseValue("anchorY",value: 0.2)
        try p.setBaseValue("cropLeft",value: 0.1)
        p.geometry?.blend = .screen; p.geometry?.flipHorizontal = true
        let clip = project.tracks[0].clips[0].id
        let edit = try ProjectTransaction(.properties(clip: clip,p),project: project)
        let animated = try TimelineCommand.animation(clip: clip,target: .property("cropLeft"),edit: .paste([Keyframe(frame: 0,value: 0),Keyframe(frame: 30,value: 0.5)],at: 0)).applying(to: edit.after)
        XCTAssertEqual(animated.clip(clip)?.properties.value("cropLeft",at: 15),0.25)
        XCTAssertEqual(edit.before,project)
        XCTAssertEqual(try JSONDecoder().decode(RenderProject.self,from: JSONEncoder().encode(animated)),animated)
    }
    func testDefaultGeometryPreservesExistingProperties() throws {
        let p = ClipProperties()
        XCTAssertEqual(p.value("scaleX",at: 0),1); XCTAssertEqual(p.value("scaleY",at: 0),1)
        XCTAssertEqual(p.value("anchorX",at: 0),0.5); XCTAssertEqual(p.value("cropBottom",at: 0),0)
        var changed = p
        XCTAssertThrowsError(try changed.setBaseValue("cropLeft",value: -0.1))
        XCTAssertThrowsError(try changed.setBaseValue("scaleY",value: .infinity))
        XCTAssertEqual(changed,p)
    }
}
