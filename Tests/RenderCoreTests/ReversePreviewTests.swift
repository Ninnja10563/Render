import XCTest
@testable import RenderCore

final class ReversePreviewTests: XCTestCase {
    func testReverseClockBoundsAndCatchUp() {
        let clock = ReversePreviewClock(origin: 300,frameRate: FrameRate(),speed: 1)
        XCTAssertEqual(clock.frame(elapsed: 0),300)
        XCTAssertEqual(clock.frame(elapsed: 0.5),285)
        XCTAssertEqual(clock.frame(elapsed: 3),210)
        XCTAssertEqual(clock.frame(elapsed: 100),0)
        XCTAssertEqual(clock.frame(elapsed: .infinity),300)
        XCTAssertEqual(clock.frame(elapsed: -1),300)
        XCTAssertEqual(ReversePreviewClock(origin: 300,frameRate: FrameRate(),speed: 4).frame(elapsed: 0.5),240)
        XCTAssertEqual(ReversePreviewClock(origin: -1,frameRate: FrameRate(),speed: .nan).frame(elapsed: 0),0)
    }
    func testFractionalRateUsesElapsedTimeWithoutAccumulatingFrameError() {
        let clock = ReversePreviewClock(origin: 100000,frameRate: FrameRate(30000,1001),speed: 2)
        XCTAssertEqual(clock.frame(elapsed: 1001),40000)
        XCTAssertEqual(clock.frame(elapsed: 0.001),100000)
    }
}
