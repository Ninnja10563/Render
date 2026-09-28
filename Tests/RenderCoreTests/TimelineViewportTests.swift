import XCTest
@testable import RenderCore

final class TimelineViewportTests: XCTestCase {
    func testLargeTrackListOnlyRequestsViewportAndOverscan() {
        let rows = TimelineViewport.rows(count: 10000,rowHeight: 70,headerHeight: 28,offset: 350028,height: 280)
        XCTAssertEqual(rows,4998..<5006)
        XCTAssertEqual(TimelineViewport.rows(count: 10000,rowHeight: 70,headerHeight: 28,offset: 350097,height: 280),4998..<5007)
    }
    func testTopBottomBounceAndEmptyWindowsStayInBounds() {
        XCTAssertEqual(TimelineViewport.rows(count: 3,rowHeight: 70,headerHeight: 28,offset: -200,height: 300),0..<3)
        XCTAssertEqual(TimelineViewport.rows(count: 3,rowHeight: 70,headerHeight: 28,offset: 10000,height: 300),1..<3)
        XCTAssertEqual(TimelineViewport.rows(count: 0,rowHeight: 70,headerHeight: 28,offset: 0,height: 300),0..<0)
        XCTAssertEqual(TimelineViewport.rows(count: 100,rowHeight: 70,headerHeight: 28,offset: .nan,height: 300),0..<0)
    }
    func testAllVisibleRowsRemainIncludedDuringScrolling() {
        for offset in stride(from: 0.0,to: 7000,by: 13) {
            let rows = TimelineViewport.rows(count: 100,rowHeight: 70,headerHeight: 28,offset: offset,height: 243)
            XCTAssertLessThanOrEqual(rows.count,9)
            for row in 0..<100 where Double(row + 1) * 70 + 28 > offset && Double(row) * 70 + 28 < offset + 243 { XCTAssertTrue(rows.contains(row)) }
        }
    }
}
