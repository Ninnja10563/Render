import XCTest
@testable import RenderCore

final class AnimationSamplerTests: XCTestCase {
    func testCompiledSamplerMatchesCurvesAcrossInterpolationAndBoundaries() {
        for mode in Interpolation.allCases {
            let curve = AnimationCurve(keys: [Keyframe(frame: 120,value: 0.2),Keyframe(frame: 0,value: 0.8,interpolation: mode),Keyframe(frame: 60,value: 1,interpolation: mode)])
            let sampler = AnimationSampler(curve)
            for frame in stride(from: -10.0,through: 130,by: 0.25) { XCTAssertEqual(sampler.value(at: frame,fallback: 0),curve.value(at: frame,fallback: 0),accuracy: 1e-10) }
            XCTAssertEqual(sampler.value(at: Double(60).nextDown,fallback: 0),curve.value(at: Double(60).nextDown,fallback: 0),accuracy: 1e-10)
        }
        XCTAssertEqual(AnimationSampler(AnimationCurve()).value(at: 0,fallback: 0.7),0.7)
    }
}
