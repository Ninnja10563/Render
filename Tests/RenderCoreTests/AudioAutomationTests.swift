import XCTest
@testable import RenderCore

final class AudioAutomationTests: XCTestCase {
    func testLongConstantClipNeedsOneRamp() {
        let ramps = AudioAutomation.ramps(curve: AnimationCurve(keys: [Keyframe(frame: 0,value: 0.5)]),offset: 0,duration: 1_000_000,fallback: 1)
        XCTAssertEqual(ramps.count,1)
        XCTAssertEqual(ramps[0].start,0); XCTAssertEqual(ramps[0].end,1_000_000)
        XCTAssertEqual(ramps[0].from,0.5); XCTAssertEqual(ramps[0].to,0.5)
    }
    func testLinearRampRespectsTrimmedAnimationPhase() {
        let curve = AnimationCurve(keys: [Keyframe(frame: 0,value: 0),Keyframe(frame: 100,value: 1)])
        let ramps = AudioAutomation.ramps(curve: curve,offset: 25,duration: 50,fallback: 1)
        XCTAssertEqual(ramps.count,1)
        XCTAssertEqual(ramps[0].from,0.25); XCTAssertEqual(ramps[0].to,0.75)
        XCTAssertEqual(ramps[0].start,0); XCTAssertEqual(ramps[0].end,50)
    }
    func testHoldDoesNotFadeBeforeNextKey() {
        let curve = AnimationCurve(keys: [Keyframe(frame: 0,value: 0,interpolation: .hold),Keyframe(frame: 100,value: 1)])
        let ramps = AudioAutomation.ramps(curve: curve,offset: 0,duration: 200,fallback: 1)
        XCTAssertEqual(ramps.count,2)
        XCTAssertEqual(ramps[0].to,0)
        XCTAssertEqual(ramps[1].from,1); XCTAssertEqual(ramps[1].to,1)
    }
    func testEaseApproximationIsBoundedAndAccurate() {
        let curve = AnimationCurve(keys: [Keyframe(frame: 0,value: 0,interpolation: .easeInOut),Keyframe(frame: 1_000_000,value: 4)])
        let ramps = AudioAutomation.ramps(curve: curve,offset: 0,duration: 1_000_000,fallback: 1)
        XCTAssertEqual(ramps.count,64)
        for ramp in ramps {
            let midpoint = Double(ramp.start + ramp.end) / 2
            XCTAssertEqual((ramp.from + ramp.to) / 2,curve.value(at: midpoint,fallback: 1),accuracy: 0.001)
        }
    }
}
