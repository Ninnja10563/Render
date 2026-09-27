import XCTest
@testable import RenderMedia

private actor DecodeCounter {
    var active = 0
    var maximum = 0
    func enter() { active += 1; maximum = max(maximum,active) }
    func leave() { active -= 1 }
}
final class MediaDecodeGateTests: XCTestCase {
    func testConcurrentDecodeWorkNeverExceedsLimit() async {
        let gate = MediaDecodeGate(limit: 2), counter = DecodeCounter()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    await gate.acquire(); await counter.enter()
                    try? await Task.sleep(nanoseconds: 1_000_000)
                    await counter.leave(); await gate.release()
                }
            }
        }
        let maximum = await counter.maximum, active = await counter.active
        XCTAssertLessThanOrEqual(maximum,2); XCTAssertEqual(active,0)
    }
}
