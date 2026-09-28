import XCTest
@testable import RenderCore

final class ShortcutTests: XCTestCase {
    func testDefaultsDistinguishSourceTimelineAndModifiers() throws {
        let map = EditorShortcutMap(); try map.validate()
        XCTAssertEqual(map.action(for: .init("o"),in: .source),.markOut)
        XCTAssertEqual(map.action(for: .init("o"),in: .timeline),.rollTool)
        XCTAssertEqual(map.action(for: .init("left",shift: true),in: .source),.previousTenFrames)
        XCTAssertEqual(map.action(for: .init("left"),in: .timeline),.previousFrame)
        XCTAssertNil(map.action(for: .init("b"),in: .source))
        XCTAssertNil(map.action(for: .init("b",control: true),in: .timeline))
    }
    func testRemappingAndClearingPersistAcrossRoundTrip() throws {
        var map = EditorShortcutMap()
        try map.assign(.init("Q",option: true),to: .bladeTool)
        try map.assign(nil,to: .playPause)
        let loaded = try JSONDecoder().decode(EditorShortcutMap.self,from: JSONEncoder().encode(map))
        try loaded.validate(); XCTAssertEqual(map,loaded)
        XCTAssertNil(loaded.action(for: .init("b"),in: .timeline))
        XCTAssertNil(loaded.action(for: .init("space"),in: .source))
        XCTAssertEqual(loaded.action(for: .init("q",option: true),in: .timeline),.bladeTool)
    }
    func testConflictsAreTransactionalAndRespectBothContexts() throws {
        var map = EditorShortcutMap(); let before = map
        XCTAssertThrowsError(try map.assign(.init("j"),to: .bladeTool))
        XCTAssertThrowsError(try map.assign(.init("o"),to: .nextFrame))
        XCTAssertEqual(map,before)
        // Clear before transferring an assignment; reset of just one command must not steal it.
        try map.assign(nil,to: .bladeTool); try map.assign(.init("b"),to: .selectTool)
        let reassigned = map
        XCTAssertThrowsError(try map.assign(EditorShortcutAction.bladeTool.defaultShortcut,to: .bladeTool))
        XCTAssertEqual(map,reassigned)
        try map.assign(.init("q"),to: .markOut); try map.assign(.init("q"),to: .bladeTool)
        XCTAssertEqual(map.action(for: .init("q"),in: .source),.markOut)
        XCTAssertEqual(map.action(for: .init("q"),in: .timeline),.bladeTool)
        try map.validate()
    }
    func testRejectsInvalidPersistedDataAndReservedKeys() throws {
        var map = EditorShortcutMap()
        for key in ["escape","return","tab","ab","é","⌘","", "!"] {
            XCTAssertThrowsError(try map.assign(.init(key),to: .bladeTool))
        }
        for json in [
            #"{"version":2,"overrides":{},"disabled":[]}"#,
            #"{"version":1,"overrides":{"unknown":{"key":"q","shift":false,"option":false,"control":false}},"disabled":[]}"#,
            #"{"version":1,"overrides":{"bladeTool":{"key":"j","shift":false,"option":false,"control":false}},"disabled":[]}"#,
            #"{"version":1,"overrides":{},"disabled":["unknown"]}"#
        ] {
            let loaded = try JSONDecoder().decode(EditorShortcutMap.self,from: Data(json.utf8))
            XCTAssertThrowsError(try loaded.validate())
        }
    }
}
