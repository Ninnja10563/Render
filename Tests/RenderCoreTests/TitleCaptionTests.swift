import XCTest
@testable import RenderCore

final class TitleCaptionTests: XCTestCase {
    func testGeneratedTitleNeedsNoSourceAssetAndSupportsEditing() throws {
        let original = RenderProject()
        let transaction = try ProjectTransaction(.addTitle(TitleContent(text: "Hello"),at: 0,duration: 90),project: original)
        var project = transaction.after
        XCTAssertTrue(project.assets.isEmpty)
        let clip = try XCTUnwrap(project.tracks[0].clips.first)
        XCTAssertNil(clip.assetID)
        project = try TimelineCommand.animation(clip: clip.id,target: .property("opacity"),edit: .set(frame: 0,value: 0)).applying(to: project)
        project = try TimelineCommand.split(clips: [clip.id],at: 30).applying(to: project)
        XCTAssertEqual(project.tracks[0].clips.count,2)
        XCTAssertEqual(project.tracks[0].clips[1].title?.text,"Hello")
        XCTAssertThrowsError(try TimelineCommand.slip(clip: clip.id,delta: 1).applying(to: project))
        let decoded = try JSONDecoder().decode(RenderProject.self,from: JSONEncoder().encode(project))
        XCTAssertEqual(decoded,project); XCTAssertEqual(transaction.before,original)
    }
    func testInvalidTitleSourceAndStylingRejected() throws {
        var project = try TimelineCommand.addTitle(TitleContent(),at: 0,duration: 30).applying(to: RenderProject())
        project.tracks[0].clips[0].assetID = UUID()
        XCTAssertThrowsError(try project.validate())
        project.tracks[0].clips[0].assetID = nil
        project.tracks[0].clips[0].title?.fontSize = .nan
        XCTAssertThrowsError(try project.validate())
    }
    func testSRTUnicodeMultilineBOMAndFractionalRateRoundTrip() throws {
        let input = "\u{FEFF}1\r\n00:00:00,000 --> 00:00:01,001\r\nHello <i>world</i>\r\n日本語\r\n\r\n2\r\n00:00:01,500 --> 00:00:02,502\r\nSecond\r\n"
        let rate = FrameRate(30000,1001)
        let cues = try SRTCodec.decode(input,rate: rate)
        XCTAssertEqual(cues.count,2); XCTAssertEqual(cues[0].text,"Hello world\n日本語")
        XCTAssertEqual(cues[0].end,30)
        let encoded = try SRTCodec.encode(cues,rate: rate)
        XCTAssertEqual(try SRTCodec.decode(encoded,rate: rate),cues)
    }
    func testMalformedAndOverflowingSRTIsRejected() {
        for input in ["1\ninvalid\nHello", "1\n00:61:00,000 --> 00:62:00,000\nHello", "1\n999999999999999999999:00:00,000 --> 01:00:00,000\nHello", "1\n00:00:02,000 --> 00:00:01,000\nHello", "1\n00:00:00,000 --> 00:00:01,000\n"] {
            XCTAssertThrowsError(try SRTCodec.decode(input,rate: FrameRate()))
        }
    }
    func testOverlappingCaptionsReceiveSeparateLanesWithoutChangingTiming() throws {
        let cues = [CaptionCue(start: 0,end: 60,text: "First"),CaptionCue(start: 30,end: 90,text: "Second"),CaptionCue(start: 60,end: 120,text: "Third")]
        let project = try TimelineCommand.captions(cues).applying(to: RenderProject())
        XCTAssertEqual(project.tracks[0].clips.map(\.start),[0,60])
        XCTAssertEqual(project.tracks[1].clips.map(\.start),[30])
        XCTAssertTrue(project.tracks[0].clips.allSatisfy { $0.title?.role == .caption })
        try project.validate()
    }
    func testLegacyMediaClipDecodingKeepsItsSource() async throws {
        var original = TimelineTests().fixture(); original.schemaVersion = 3
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try JSONEncoder().encode(original).write(to: file)
        let migrated = try await ProjectStore().load(file)
        original.schemaVersion = RenderProject.currentSchema
        XCTAssertEqual(migrated,original)
        XCTAssertNil(migrated.tracks[0].clips[0].title)
    }
}
