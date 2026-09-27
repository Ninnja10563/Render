import XCTest
@testable import RenderCore

final class TimelinePerformanceTests: XCTestCase {
    func testThousandClipGroupMovePerformance() throws {
        var project = RenderProject()
        let asset = MediaAsset(url: URL(fileURLWithPath: "/tmp/stress.mov"),kind: .video,duration: 60)
        project.assets = [asset]
        project.tracks[0].clips = (0..<1000).map { TimelineClip(assetID: asset.id,name: "Clip \($0)",start: Int64($0 * 30),duration: 30) }
        let ids = Set(project.tracks[0].clips.map(\.id))
        let command = TimelineCommand.move(clips: ids,delta: 30)
        let moved = try command.applying(to: project)
        XCTAssertEqual(moved.duration,project.duration + 30)
        XCTAssertEqual(moved.tracks[0].clips.map(\.sourceIn),project.tracks[0].clips.map(\.sourceIn))
        measure { _ = try! command.applying(to: project) }
    }
}
