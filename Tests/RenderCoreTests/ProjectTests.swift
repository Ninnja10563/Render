import XCTest
@testable import RenderCore

final class ProjectTests: XCTestCase {
    func testRationalFrameRateRoundTrip() {
        let rate = FrameRate(30000,1001)
        for frame: Int64 in [0,1,1798,107892,1_000_000] { XCTAssertEqual(rate.frames(rate.seconds(frame)), frame) }
        XCTAssertEqual(FrameRate().timecode(108001), "01:00:00:01")
    }
    func testAnimationInterpolationAndHold() {
        var curve = AnimationCurve(keys: [Keyframe(frame: 0, value: 0),Keyframe(frame: 10, value: 1)])
        XCTAssertEqual(curve.value(at: 5, fallback: 8), 0.5)
        XCTAssertEqual(curve.value(at: -1, fallback: 8), 0)
        XCTAssertEqual(curve.value(at: 20, fallback: 8), 1)
        curve.keys[0].interpolation = .hold
        XCTAssertEqual(curve.value(at: 9, fallback: 8), 0)
        curve.keys[0].interpolation = .easeIn
        XCTAssertEqual(curve.value(at: 5, fallback: 8), 0.25)
        curve.keys[0].interpolation = .easeOut
        XCTAssertEqual(curve.value(at: 5, fallback: 8), 0.75)
    }
    func testKeyReplacementAndSorting() {
        var curve = AnimationCurve()
        curve.set(Keyframe(frame: 20,value: 1)); curve.set(Keyframe(frame: 0,value: 0)); curve.set(Keyframe(frame: 20,value: 2))
        XCTAssertEqual(curve.keys.map(\.frame), [0,20])
        XCTAssertEqual(curve.value(at: 20, fallback: 0), 2)
    }
    func testProjectAtomicSaveAndRoundTrip() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Edit.renderproject")
        let store = ProjectStore()
        var project = TimelineTests().fixture()
        try await store.save(project, to: url)
        let read = try await store.load(url)
        XCTAssertEqual(project, read)
        project.name = "Saved again"
        try await store.save(project, to: url)
        let updated = try await store.load(url)
        XCTAssertEqual(updated.name, "Saved again")
        project.settings.width = -1
        do { try await store.save(project, to: url); XCTFail("Invalid project saved") } catch {}
        let intact = try await store.load(url)
        XCTAssertEqual(intact.name, "Saved again")
    }
    func testFutureSchemaRejectedBeforeFullDecode() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("{\"schemaVersion\":999}".utf8).write(to: url)
        do { _ = try await ProjectStore().load(url); XCTFail("Future schema accepted") }
        catch { XCTAssertEqual(error as? RenderError, .unsupportedVersion(999)) }
    }
    func testDuplicateIdentityAndInvalidEffectsRejected() {
        var p = TimelineTests().fixture()
        p.assets.append(p.assets[0]); XCTAssertThrowsError(try p.validate())
        p.assets.removeLast()
        var effect = Effect(kind: .gaussianBlur); effect.amount = -1
        p.tracks[0].clips[0].effects = [effect]; XCTAssertThrowsError(try p.validate())
    }
    func testExportSettingsRejectOddOrExtremeSizes() {
        var config = ExportConfiguration(); config.width = 1919
        XCTAssertThrowsError(try config.validate())
        config.width = 1920; config.frameRate = FrameRate(0)
        XCTAssertThrowsError(try config.validate())
        config.frameRate = FrameRate(24000,1001)
        XCTAssertNoThrow(try config.validate())
    }
    func testInvalidAnimationRejected() {
        var p = TimelineTests().fixture()
        p.tracks[0].clips[0].properties.animations["opacity"] = AnimationCurve(keys: [Keyframe(frame: 1,value: 3)])
        XCTAssertThrowsError(try p.validate())
    }
}
