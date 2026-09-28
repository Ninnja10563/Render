import XCTest
@testable import RenderCore

final class EditingTimeTests: XCTestCase {
    func testUserEnteredTimeCannotTrapIntegerConversion() throws {
        let rate = FrameRate(30000,1001)
        XCTAssertEqual(try rate.editingFrames(1),30)
        XCTAssertEqual(try rate.editingFrames(0),0)
        for value in [-1,Double.nan,Double.infinity,Double.greatestFiniteMagnitude,1e30] {
            XCTAssertThrowsError(try rate.editingFrames(value))
        }
        XCTAssertThrowsError(try FrameRate(0).editingFrames(1))
        XCTAssertThrowsError(try FrameRate(30,0).editingFrames(1))
        XCTAssertThrowsError(try FrameRate(30).editingFrames(100_000_000 / 30.0))
    }
}
