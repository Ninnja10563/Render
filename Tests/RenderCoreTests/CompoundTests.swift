import XCTest
@testable import RenderCore

final class CompoundTests: XCTestCase {
    func testCreateEditContextAndBreakApartPreserveSourcesAndTiming() throws {
        let original = TimelineTests().fixture(), selected = Set(TimelineTests().fixture().tracks[0].clips.map(\.id))
        XCTAssertThrowsError(try TimelineCommand.makeCompound(clips: selected,name: "Missing").applying(to: original))
        let transaction = try ProjectTransaction(.makeCompound(clips: Set(original.tracks[0].clips.map(\.id)),name: "Scene"),project: original)
        let grouped = transaction.after, source = try XCTUnwrap(grouped.compounds?.first)
        let parent = try XCTUnwrap(grouped.tracks.flatMap(\.clips).first { $0.compoundID == source.id })
        XCTAssertEqual(grouped.duration,600); XCTAssertEqual(grouped.assets,original.assets); XCTAssertEqual(source.tracks[0].clips,original.tracks[0].clips)
        XCTAssertEqual(transaction.before,original)
        var context = try grouped.timelineContext(compoundID: source.id)
        context = try TimelineCommand.trim(clip: context.tracks[0].clips[0].id,edge: .trailing,to: 150).applying(to: context)
        let edited = try grouped.replacingContext(context,compoundID: source.id)
        XCTAssertEqual(edited.clip(parent.id)?.duration,600)
        let expanded = try TimelineCommand.breakApart(parent.id).applying(to: edited)
        let restored = expanded.tracks.flatMap(\.clips).sorted { $0.start < $1.start }
        XCTAssertEqual(restored.map(\.start),[0,300]); XCTAssertEqual(restored.map(\.duration),[150,300])
        XCTAssertTrue(restored.allSatisfy { $0.compoundID == nil })
        XCTAssertEqual(try JSONDecoder().decode(RenderProject.self,from: JSONEncoder().encode(edited)),edited)
    }
    func testCyclesDepthAndUnavailableSourceAreRejected() throws {
        var p = RenderProject()
        var source = CompoundSource(name: "Cycle",kind: .video,settings: p.settings,duration: 30,tracks: [TimelineTrack(name: "Inside",kind: .video)])
        var child = TimelineClip(assetID: nil,name: "Cycle",start: 0,duration: 30); child.compoundID = source.id
        source.tracks[0].clips = [child]; p.compounds = [source]
        XCTAssertThrowsError(try p.validate())
        p.compounds = []; var previous: UUID?
        for index in 0..<9 {
            var track = TimelineTrack(name: "Inside",kind: .video)
            if let previous { var clip = TimelineClip(assetID: nil,name: "Child",start: 0,duration: 30); clip.compoundID = previous; track.clips = [clip] }
            let node = CompoundSource(name: "Level \(index)",kind: .video,settings: p.settings,duration: 30,tracks: [track])
            p.compounds!.append(node); previous = node.id
        }
        XCTAssertThrowsError(try p.validate())
        p.compounds!.removeLast(); try p.validate()
        var missing = TimelineClip(assetID: nil,name: "Missing",start: 0,duration: 30); missing.compoundID = UUID(); p.tracks[0].clips = [missing]
        XCTAssertThrowsError(try p.validate())
    }
    func testMagneticConnectedSelectionAndRestoration() throws {
        var p = TimelineTests().fixture(); let anchor = p.tracks[0].clips[0]
        p = try TimelineCommand.storyline(enabled: true,track: p.tracks[0].id).applying(to: p)
        p = try TimelineCommand.addTitle(TitleContent(text: "Connected"),at: 30,duration: 60).applying(to: p)
        let title = try XCTUnwrap(p.tracks.first?.clips.first)
        p = try TimelineCommand.connection(clip: title.id,anchor: anchor.id).applying(to: p)
        let grouped = try TimelineCommand.makeCompound(clips: [anchor.id],name: "Connected scene").applying(to: p)
        let parent = try XCTUnwrap(grouped.tracks.flatMap(\.clips).first { $0.compoundID != nil })
        XCTAssertNil(grouped.clip(title.id)); XCTAssertEqual(grouped.compounds?.first?.tracks.flatMap(\.clips).count,2)
        let restored = try TimelineCommand.breakApart(parent.id).applying(to: grouped)
        let restoredTitle = try XCTUnwrap(restored.tracks.flatMap(\.clips).first { $0.title != nil })
        XCTAssertEqual(restoredTitle.start,30); XCTAssertNotNil(restoredTitle.connection); XCTAssertEqual(restored.duration,600)
    }
    func testBreakApartRefusesToDiscardGroupProcessing() throws {
        let original = TimelineTests().fixture()
        var p = try TimelineCommand.makeCompound(clips: Set(original.tracks[0].clips.map(\.id)),name: "Scene").applying(to: original)
        let parent = try XCTUnwrap(p.tracks.flatMap(\.clips).first { $0.compoundID != nil })
        var properties = parent.properties; properties.opacity = 0.5
        p = try TimelineCommand.properties(clip: parent.id,properties).applying(to: p)
        XCTAssertThrowsError(try TimelineCommand.breakApart(parent.id).applying(to: p))
        let before = p
        XCTAssertThrowsError(try TimelineCommand.makeCompound(clips: [parent.id],name: "").applying(to: p))
        XCTAssertEqual(p,before)
    }
}
