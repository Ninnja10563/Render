import XCTest
@testable import RenderCore

final class LeadingHandleTests: XCTestCase {
    func fixture() -> RenderProject {
        var project = RenderProject()
        let media = MediaAsset(url: URL(fileURLWithPath: "/video.mov"),kind: .video,duration: 10)
        project.assets = [media]
        var clip = TimelineClip(assetID: media.id,name: "Handles",start: 30,duration: 60); clip.sourceIn = 2
        clip.properties.animations["opacity"] = AnimationCurve(keys: [Keyframe(frame: 0,value: 0.2),Keyframe(frame: 30,value: 1)])
        var effect = Effect(kind: .exposure); effect.animation = AnimationCurve(keys: [Keyframe(frame: 5,value: -1),Keyframe(frame: 50,value: 1)])
        clip.effects = [effect]; clip.properties.audioFades = ClipAudioFades(start: 0,end: 60,fadeIn: 15,fadeOut: 15)
        project.tracks[0].clips = [clip]; return project
    }
    func testLeadingExtensionPreservesPropertyEffectAndFadePhasesAndUndo() throws {
        let project = fixture(), old = project.tracks[0].clips[0]
        let transaction = try ProjectTransaction(.trim(clip: old.id,edge: .leading,to: 15),project: project)
        let clip = transaction.after.tracks[0].clips[0]
        XCTAssertEqual(clip.start,15); XCTAssertEqual(clip.duration,75); XCTAssertEqual(clip.sourceIn,1.5)
        XCTAssertEqual(clip.animationOffset,0)
        for frame in stride(from: 0.0,through: 59,by: 0.5) {
            XCTAssertEqual(clip.properties.value("opacity",at: frame + 15),old.properties.value("opacity",at: frame),accuracy: 1e-10)
            XCTAssertEqual(clip.effects[0].animation.value(at: frame + 15,fallback: 0),old.effects[0].animation.value(at: frame,fallback: 0),accuracy: 1e-10)
            XCTAssertEqual(clip.properties.audioFades!.gain(at: frame + 15),old.properties.audioFades!.gain(at: frame),accuracy: 1e-10)
        }
        XCTAssertEqual(transaction.before,project)
        XCTAssertEqual(try JSONDecoder().decode(RenderProject.self,from: JSONEncoder().encode(transaction.after)),transaction.after)
        var noHandles = project; noHandles.tracks[0].clips[0].sourceIn = 0
        XCTAssertThrowsError(try TimelineCommand.trim(clip: old.id,edge: .leading,to: 15).applying(to: noHandles))
    }
    func testRollAndSlideCanRevealUnusedRightHandles() throws {
        var project = fixture(); var before = project.tracks[0].clips[0]
        before.id = UUID(); before.start = 0; before.duration = 30; before.sourceIn = 0; before.properties = ClipProperties(); before.effects = []
        project.tracks[0].clips.insert(before,at: 0)
        let rolled = try TimelineCommand.roll(clip: before.id,boundary: 15).applying(to: project)
        XCTAssertEqual(rolled.tracks[0].clips[1].sourceIn,1.5)
        XCTAssertEqual(rolled.tracks[0].clips[1].properties.animations["opacity"]?.keys.first?.frame,15)
        var after = project.tracks[0].clips[1]; after.id = UUID(); after.start = 90; after.sourceIn = 3
        project.tracks[0].clips.append(after)
        let slid = try TimelineCommand.slide(clip: project.tracks[0].clips[1].id,delta: -10).applying(to: project)
        XCTAssertEqual(slid.tracks[0].clips[2].start,80)
        XCTAssertEqual(slid.tracks[0].clips[2].properties.animations["opacity"]?.keys.first?.frame,10)
    }
    func testGeneratedClipsExtendAndConnectionsKeepTheirOriginalContentAnchor() throws {
        var project = fixture(); let anchor = project.tracks[0].clips[0]
        project.storyline = StorylineSettings(enabled: false,trackID: project.tracks[0].id)
        var title = TimelineClip(assetID: nil,name: "Connected",start: 45,duration: 30); title.title = TitleContent(text: "Connected")
        title.connection = ClipConnection(anchor: anchor.id,offset: 15)
        var titleTrack = TimelineTrack(name: "Titles",kind: .video); titleTrack.clips = [title]; project.tracks.insert(titleTrack,at: 0)
        let trimmed = try TimelineCommand.trim(clip: anchor.id,edge: .leading,to: 15).applying(to: project)
        XCTAssertEqual(trimmed.clip(title.id)?.start,45)
        XCTAssertEqual(trimmed.clip(title.id)?.connection?.offset,30)
        let ripple = try TimelineCommand.rippleTrim(clip: anchor.id,edge: .leading,to: 15).applying(to: project)
        XCTAssertEqual(ripple.clip(title.id)?.start,60)
        var generated = project; generated.storyline = nil; generated.tracks[0].clips[0].connection = nil
        let extended = try TimelineCommand.trim(clip: title.id,edge: .leading,to: 0).applying(to: generated)
        XCTAssertEqual(extended.clip(title.id)?.duration,75); XCTAssertEqual(extended.clip(title.id)?.sourceIn,0)
        project.tracks[0].locked = true
        XCTAssertThrowsError(try TimelineCommand.rippleTrim(clip: anchor.id,edge: .leading,to: 15).applying(to: project))
    }
    func testCompoundSlipUsesItsStoredSourceHandles() throws {
        let project = fixture(), original = project.tracks[0].clips[0]
        var grouped = try CompoundEditing.create([original.id],name: "Scene",in: project)
        let parent = grouped.tracks.flatMap(\.clips).first!
        grouped = try TimelineCommand.trim(clip: parent.id,edge: .trailing,to: parent.start + 30).applying(to: grouped)
        let slipped = try TimelineCommand.slip(clip: parent.id,delta: 15).applying(to: grouped)
        XCTAssertEqual(slipped.clip(parent.id)?.sourceIn,0.5)
        XCTAssertEqual(slipped.clip(parent.id)?.duration,30)
        XCTAssertThrowsError(try TimelineCommand.slip(clip: parent.id,delta: 60).applying(to: grouped))
    }
}
