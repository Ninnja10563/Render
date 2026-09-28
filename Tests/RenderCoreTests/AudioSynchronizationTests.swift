import XCTest
@testable import RenderCore

final class AudioSynchronizationTests: XCTestCase {
    func signal(count: Int) -> [Float] {
        var seed: UInt64 = 7
        return (0..<count).map { _ in
            seed = seed &* 6364136223846793005 &+ 1
            return Float((seed >> 32) % 10000) / 10000
        }
    }
    func testPositiveAndNegativeOffsetWithGainAndNoise() throws {
        let reference = signal(count: 1800)
        let target = Array(reference[137..<1537]).enumerated().map { index,value in value * 0.4 + Float(index % 7) * 0.001 }
        let forward = try AudioSynchronization.match(reference: reference,target: target,maximumOffset: 300,minimumOverlap: 500)
        XCTAssertEqual(forward.offset,137); XCTAssertGreaterThan(forward.correlation,0.99)
        let backward = try AudioSynchronization.match(reference: target,target: reference,maximumOffset: 300,minimumOverlap: 500)
        XCTAssertEqual(backward.offset,-137)
    }
    func testSilencePeriodicAndUnrelatedAudioAreRejected() {
        let silence = [Float](repeating: 0,count: 1000)
        XCTAssertThrowsError(try AudioSynchronization.match(reference: silence,target: silence,maximumOffset: 200,minimumOverlap: 500))
        let periodic = (0..<1000).map { Float(sin(Double($0) * .pi / 20) + 1) }
        XCTAssertThrowsError(try AudioSynchronization.match(reference: periodic,target: periodic,maximumOffset: 200,minimumOverlap: 500))
        let signal = signal(count: 2000)
        XCTAssertThrowsError(try AudioSynchronization.match(reference: Array(signal.prefix(1000)),target: Array(signal.suffix(1000)),maximumOffset: 200,minimumOverlap: 500))
    }
    func testBoundsAndNonfiniteSamplesAreRejected() {
        XCTAssertThrowsError(try AudioSynchronization.match(reference: [],target: [],maximumOffset: 10,minimumOverlap: 100))
        let invalid = [Float](repeating: .nan,count: 1000)
        XCTAssertThrowsError(try AudioSynchronization.match(reference: invalid,target: invalid,maximumOffset: 10,minimumOverlap: 100))
        let valid = signal(count: 1000)
        XCTAssertThrowsError(try AudioSynchronization.match(reference: valid,target: valid,maximumOffset: Int.max,minimumOverlap: 100))
    }
}
