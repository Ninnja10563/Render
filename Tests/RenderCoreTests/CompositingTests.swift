import XCTest
@testable import RenderCore

final class CompositingTests: XCTestCase {
    func testChromaKeyRemovesScreenAndPreservesForeground() {
        let key = ChromaKeySettings()
        let green = key.sample(red: 0,green: 1,blue: 0,tolerance: 0.15)
        XCTAssertEqual(green.3,0); XCTAssertEqual(green.1,0)
        let red = key.sample(red: 1,green: 0,blue: 0,tolerance: 0.15)
        XCTAssertEqual(red.3,1); XCTAssertEqual(red.0,1)
        let neutral = key.sample(red: 0.5,green: 0.5,blue: 0.5,tolerance: 0.15)
        XCTAssertEqual(neutral.3,1)
    }
    func testKeyerEdgeIsFiniteAndPremultiplied() {
        var key = ChromaKeySettings(); key.softness = 0
        for green in stride(from: 0.0,through: 1,by: 0.01) {
            let p = key.sample(red: 0.2,green: green,blue: 0.1,tolerance: 0.3)
            XCTAssertTrue([p.0,p.1,p.2,p.3].allSatisfy { $0.isFinite && (0...1).contains($0) })
            XCTAssertLessThanOrEqual(max(p.0,p.1,p.2),p.3 + 0.0001)
        }
    }
    func testMaskAndKeyerValidationProtectsRendering() {
        var mask = EffectMask(); XCTAssertNoThrow(try mask.validate())
        mask.points.removeLast(); XCTAssertThrowsError(try mask.validate())
        mask = EffectMask(); mask.width = .infinity; XCTAssertThrowsError(try mask.validate())
        var key = ChromaKeySettings(); key.red = .nan; XCTAssertThrowsError(try key.validate())
        var project = TimelineTests().fixture(); var effect = Effect(kind: .chromaKey)
        effect.keying = key; project.tracks[0].clips[0].effects = [effect]
        XCTAssertThrowsError(try project.validate())
    }
    func testSchemaOneMigrationKeepsAllEdits() async throws {
        var legacy = TimelineTests().fixture(); legacy.schemaVersion = 1
        legacy.tracks[0].clips[0].properties.opacity = 0.4
        legacy.tracks[0].clips[0].effects = [Effect(kind: .exposure)]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try JSONEncoder().encode(legacy)
        let text = String(decoding: data,as: UTF8.self)
        XCTAssertFalse(text.contains("\"mask\"")); XCTAssertFalse(text.contains("\"keying\""))
        try data.write(to: url)
        let migrated = try await ProjectStore().load(url)
        legacy.schemaVersion = RenderProject.currentSchema
        XCTAssertEqual(migrated,legacy)
        try await ProjectStore().save(migrated,to: url)
        let reopened = try await ProjectStore().load(url)
        XCTAssertEqual(reopened,migrated)
    }
    func testExtremeAnimationOffsetRejectedBeforeTimelineArithmetic() {
        var project = TimelineTests().fixture()
        project.tracks[0].clips[0].animationOffset = Int64.max
        XCTAssertThrowsError(try project.validate())
    }
    func testMaskedEffectRoundTripAndUndo() throws {
        let project = TimelineTests().fixture(); let id = project.tracks[0].clips[0].id
        var effect = Effect(kind: .chromaKey); effect.mask = EffectMask(); effect.keying = ChromaKeySettings()
        let transaction = try ProjectTransaction(.effects(clip: id,[effect]),project: project)
        XCTAssertEqual(transaction.before,project)
        let saved = try JSONDecoder().decode(RenderProject.self,from: JSONEncoder().encode(transaction.after))
        XCTAssertEqual(saved,transaction.after)
        for kind in EffectKind.allCases { XCTAssertTrue(kind.range.contains(kind.defaultValue)) }
    }
}
