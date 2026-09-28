import XCTest
@testable import RenderCore

final class ExportQualityTests: XCTestCase {
    func testPresetsScaleWithPixelsFrameRateAndCodec() throws {
        var config = ExportConfiguration(); XCTAssertNil(config.videoBitrate)
        config.quality = .balanced
        let baseline = try XCTUnwrap(config.videoBitrate)
        config.frameRate = FrameRate(60); XCTAssertEqual(config.videoBitrate,baseline * 2)
        config.codec = .hevc; XCTAssertLessThan(try XCTUnwrap(config.videoBitrate),baseline * 2)
        config.quality = .compact; let compact = try XCTUnwrap(config.videoBitrate)
        config.quality = .high; XCTAssertGreaterThan(try XCTUnwrap(config.videoBitrate),compact)
    }
    func testCustomBoundsAndSizeEstimate() throws {
        var config = ExportConfiguration(); config.quality = .custom; config.customBitrateMbps = 10
        try config.validate(); XCTAssertEqual(config.videoBitrate,10_000_000)
        XCTAssertEqual(config.estimatedBytes(duration: 8),10_320_000)
        for value in [Double.nan,Double.infinity,-1,0,201] { config.customBitrateMbps = value; XCTAssertThrowsError(try config.validate()); XCTAssertNil(config.videoBitrate) }
        config.customBitrateMbps = 10; config.codec = .proRes
        XCTAssertThrowsError(try config.validate()); XCTAssertNil(config.videoBitrate)
    }
}
