import XCTest
@testable import RenderCore

final class AudioEffectTests: XCTestCase {
    func fixture() -> RenderProject {
        var project = RenderProject()
        let media = MediaAsset(url: URL(fileURLWithPath: "/audio.mov"),kind: .video,duration: 3,audioChannels: 2)
        project.assets = [media]
        project.tracks[0].clips = [TimelineClip(assetID: media.id,name: "Audio",start: 0,duration: 90)]
        return project
    }
    func testDescriptorsValidateParametersAndSerializeThroughUndoAndDetach() throws {
        let project = fixture(), clip = project.tracks[0].clips[0]
        for kind in AudioEffectKind.allCases {
            var properties = clip.properties; properties.audioEffects = [AudioEffect(kind: kind)]
            let transaction = try ProjectTransaction(.properties(clip: clip.id,properties),project: project)
            XCTAssertEqual(transaction.before,project)
            XCTAssertEqual(try JSONDecoder().decode(RenderProject.self,from: JSONEncoder().encode(transaction.after)),transaction.after)
            let detached = try TimelineCommand.detachAudio(clip: clip.id).applying(to: transaction.after)
            XCTAssertEqual(detached.tracks.last?.clips.first?.properties.audioEffects,properties.audioEffects)
            for parameter in kind.parameters {
                var invalid = properties; invalid.audioEffects![0].values[parameter.key] = parameter.range.upperBound + 1
                XCTAssertThrowsError(try TimelineCommand.properties(clip: clip.id,invalid).applying(to: project))
                invalid.audioEffects![0].values[parameter.key] = .nan
                XCTAssertThrowsError(try TimelineCommand.properties(clip: clip.id,invalid).applying(to: project))
            }
            var unknown = properties; unknown.audioEffects![0].values["unknown"] = 1
            XCTAssertThrowsError(try TimelineCommand.properties(clip: clip.id,unknown).applying(to: project))
        }
    }
    func testGroupBusProcessingIsRejectedInsteadOfChangingNonlinearSemantics() throws {
        let original = fixture(), clip = original.tracks[0].clips[0]
        let grouped = try CompoundEditing.create([clip.id],name: "Group",in: original)
        let parent = grouped.tracks.flatMap(\.clips).first!
        var p = parent.properties; p.audioEffects = [AudioEffect(kind: .compressor)]
        XCTAssertThrowsError(try TimelineCommand.properties(clip: parent.id,p).applying(to: grouped))
        var locked = original; locked.tracks[0].locked = true
        XCTAssertThrowsError(try TimelineCommand.properties(clip: clip.id,p).applying(to: locked))
        var tooMany = clip.properties; tooMany.audioEffects = (0..<17).map { _ in AudioEffect(kind: .equalizer) }
        XCTAssertThrowsError(try TimelineCommand.properties(clip: clip.id,tooMany).applying(to: original))
    }
}
