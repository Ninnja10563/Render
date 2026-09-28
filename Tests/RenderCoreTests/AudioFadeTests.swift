import XCTest
@testable import RenderCore

final class AudioFadeTests: XCTestCase {
    func testShapesAndOverlappingFades() throws {
        for shape in AudioFadeShape.allCases {
            let fade = ClipAudioFades(start: 30,end: 150,fadeIn: 60,fadeOut: 60,shape: shape)
            try fade.validate()
            XCTAssertEqual(fade.gain(at: 30),0,accuracy: 0.00001)
            XCTAssertEqual(fade.gain(at: 90),1,accuracy: 0.00001)
            XCTAssertEqual(fade.gain(at: 150),0,accuracy: 0.00001)
            XCTAssertEqual(fade.gain(at: 60),shape.value(0.5),accuracy: 0.00001)
        }
        let base = AudioAutomation.ramps(curve: AnimationCurve(),offset: 0,duration: 120,fallback: 1)
        let ramps = AudioAutomation.applyingFades(to: base,duration: 120,fadeIn: 120,fadeOut: 120)
        XCTAssertGreaterThan(ramps.map(\.to).max() ?? 0,0.24)
        XCTAssertLessThanOrEqual(ramps.count,64)
    }
    func testSplitTrimUndoAndSerializationPreserveEnvelope() throws {
        var project = TimelineTests().fixture()
        let id = project.tracks[0].clips[0].id
        var properties = project.tracks[0].clips[0].properties
        properties.audioFades = ClipAudioFades(start: 0,end: 300,fadeIn: 180,fadeOut: 60,shape: .smooth)
        let transaction = try ProjectTransaction(.properties(clip: id,properties),project: project)
        XCTAssertEqual(transaction.before,project); project = transaction.after
        let split = try TimelineCommand.split(clips: [id],at: 90).applying(to: project)
        let right = try XCTUnwrap(split.tracks[0].clips.first { $0.start == 90 })
        XCTAssertEqual(right.properties.audioFades,properties.audioFades)
        XCTAssertEqual(right.properties.audioFades?.gain(at: Double(right.animationOffset)),0.5)
        let trimmed = try TimelineCommand.trim(clip: id,edge: .leading,to: 30).applying(to: project)
        XCTAssertEqual(trimmed.clip(id)?.properties.audioFades,properties.audioFades)
        XCTAssertEqual(try JSONDecoder().decode(RenderProject.self,from: JSONEncoder().encode(split)),split)
    }
    func testFadeMultipliesAutomationAndRetainsPhaseInRenderHandles() {
        let fade = ClipAudioFades(start: 0,end: 300,fadeIn: 120,fadeOut: 60)
        let curve = AnimationCurve(keys: [Keyframe(frame: 0,value: 0.5),Keyframe(frame: 300,value: 1)])
        let base = AudioAutomation.ramps(curve: curve,offset: 60,duration: 180,fallback: 1)
        let ramps = AudioAutomation.applying(fade,to: base,offset: 60)
        XCTAssertEqual(ramps.first?.from ?? -1,0.3,accuracy: 0.0001)
        XCTAssertEqual(ramps.last?.to ?? -1,0.9,accuracy: 0.0001)
        XCTAssertTrue(ramps.allSatisfy { $0.end > $0.start && $0.from.isFinite && $0.to.isFinite })
        XCTAssertLessThanOrEqual(ramps.count,130)
    }
    func testInvalidAndLegacyPayloads() throws {
        XCTAssertThrowsError(try ClipAudioFades(start: 0,end: 100,fadeIn: 101).validate())
        XCTAssertThrowsError(try ClipAudioFades(start: Int64.min,end: Int64.max).validate())
        XCTAssertThrowsError(try ClipAudioFades(start: 0,end: 100,fadeOut: -1).validate())
        let data = try JSONEncoder().encode(ClipProperties())
        let decoded = try JSONDecoder().decode(ClipProperties.self,from: data)
        XCTAssertNil(decoded.audioFades)
    }
}
