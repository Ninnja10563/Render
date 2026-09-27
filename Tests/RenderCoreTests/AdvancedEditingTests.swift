import XCTest
@testable import RenderCore

final class AdvancedEditingTests: XCTestCase {
    func fixture() -> RenderProject {
        var p = TimelineTests().fixture()
        let a = p.assets[0]
        p.tracks[0].clips.append(TimelineClip(assetID: a.id,name: "C",start: 600,duration: 300))
        return p
    }
    func testRollKeepsOuterBoundariesAndAdjustsRightSource() throws {
        let p = fixture(); let id = p.tracks[0].clips[0].id
        let result = try TimelineCommand.roll(clip: id,boundary: 330).applying(to: p)
        XCTAssertEqual(result.tracks[0].clips.map(\.start),[0,330,600])
        XCTAssertEqual(result.tracks[0].clips.map(\.duration),[330,270,300])
        XCTAssertEqual(result.tracks[0].clips[1].sourceIn,1)
        XCTAssertEqual(result.duration,p.duration)
    }
    func testRollRejectsGapAndSourceOverrun() {
        var p = fixture(); let id = p.tracks[0].clips[0].id
        XCTAssertThrowsError(try TimelineCommand.roll(clip: id,boundary: 299).applying(to: p))
        p.tracks[0].clips[1].start = 301; p.tracks[0].clips[1].duration = 299
        XCTAssertThrowsError(try TimelineCommand.roll(clip: id,boundary: 330).applying(to: p))
    }
    func testSlipMovesOnlySourceWindow() throws {
        let p = fixture(); let id = p.tracks[0].clips[1].id
        let result = try TimelineCommand.slip(clip: id,delta: 60).applying(to: p)
        XCTAssertEqual(result.tracks[0].clips[1].sourceIn,2)
        XCTAssertEqual(result.tracks[0].clips.map(\.start),p.tracks[0].clips.map(\.start))
        XCTAssertEqual(result.duration,p.duration)
    }
    func testSlideAdjustsNeighborsWithoutChangingSequenceLength() throws {
        let p = fixture(); let clip = p.tracks[0].clips[1]
        let result = try TimelineCommand.slide(clip: clip.id,delta: 30).applying(to: p)
        XCTAssertEqual(result.tracks[0].clips.map(\.start),[0,330,630])
        XCTAssertEqual(result.tracks[0].clips.map(\.duration),[330,300,270])
        XCTAssertEqual(result.tracks[0].clips[1].sourceIn,clip.sourceIn)
        XCTAssertEqual(result.tracks[0].clips[2].sourceIn,1)
        XCTAssertEqual(result.duration,p.duration)
    }
    func testRippleTrimLeadingKeepsCutPosition() throws {
        let p = fixture(); let id = p.tracks[0].clips[1].id
        let result = try TimelineCommand.rippleTrim(clip: id,edge: .leading,to: 330).applying(to: p)
        XCTAssertEqual(result.tracks[0].clips.map(\.start),[0,300,570])
        XCTAssertEqual(result.tracks[0].clips[1].duration,270)
        XCTAssertEqual(result.tracks[0].clips[1].sourceIn,1)
        XCTAssertEqual(result.duration,870)
    }
    func testRippleTrimTrailingPushesFollowingClips() throws {
        let p = fixture(); let id = p.tracks[0].clips[0].id
        let result = try TimelineCommand.rippleTrim(clip: id,edge: .trailing,to: 330).applying(to: p)
        XCTAssertEqual(result.tracks[0].clips.map(\.start),[0,330,630])
        XCTAssertEqual(result.duration,930)
    }
    func testOverwritePreservesBothSurvivingSides() throws {
        var p = fixture()
        let replacement = MediaAsset(url: URL(fileURLWithPath: "/tmp/insert.mov"),kind: .video,duration: 2)
        p.assets.append(replacement)
        let result = try TimelineCommand.overwrite(asset: replacement.id,track: p.tracks[0].id,at: 90).applying(to: p)
        let clips = result.tracks[0].clips.sorted { $0.start < $1.start }
        XCTAssertEqual(clips.map(\.start),[0,90,150,300,600])
        XCTAssertEqual(clips.map(\.duration),[90,60,150,300,300])
        XCTAssertEqual(clips[2].sourceIn,5)
        XCTAssertEqual(result.duration,p.duration)
    }
    func testMultitrackPastePreservesSynchronizationAndIsAtomic() throws {
        var p = fixture()
        let audio = MediaAsset(url: URL(fileURLWithPath: "/tmp/a.wav"),kind: .audio,duration: 60)
        p.assets.append(audio)
        p.tracks[1].clips = [TimelineClip(assetID: audio.id,name: "Audio",start: 30,duration: 120)]
        let lanes = [ClipboardLane(trackID: p.tracks[0].id,clips: [p.tracks[0].clips[0]]),ClipboardLane(trackID: p.tracks[1].id,clips: p.tracks[1].clips)]
        let pasted = try TimelineCommand.pasteLanes(lanes,at: 900).applying(to: p)
        XCTAssertEqual(pasted.tracks[0].clips.last?.start,900)
        XCTAssertEqual(pasted.tracks[1].clips.last?.start,930)
        p.tracks[1].locked = true
        XCTAssertThrowsError(try TimelineCommand.pasteLanes(lanes,at: 900).applying(to: p))
        XCTAssertEqual(p.tracks[0].clips.count,3)
    }
    func testDetachAudioPreservesSourceSpeedAndAutomation() throws {
        var p = fixture(); p.assets[0].audioChannels = 2
        let id = p.tracks[0].clips[0].id
        p.tracks[0].clips[0].speed = 2
        p.tracks[0].clips[0].properties.animations["volume"] = AnimationCurve(keys: [Keyframe(frame: 10,value: 0.4)])
        let result = try TimelineCommand.detachAudio(clip: id).applying(to: p)
        XCTAssertTrue(result.tracks[0].clips[0].properties.muted)
        let detached = try XCTUnwrap(result.tracks.last?.clips.first)
        XCTAssertEqual(detached.speed,2)
        XCTAssertEqual(detached.start,0)
        XCTAssertEqual(detached.properties.animations["volume"],p.tracks[0].clips[0].properties.animations["volume"])
        XCTAssertEqual(result.assets.last?.url,p.assets[0].url)
        XCTAssertEqual(result.assets.last?.kind,.audio)
    }
}

extension AdvancedEditingTests {
    func testRangeDeleteSplitsSourceAndLeavesGap() throws {
        let p = fixture()
        let result = try TimelineCommand.deleteRange(track: p.tracks[0].id,start: 90,end: 150,ripple: false).applying(to: p)
        let clips = result.tracks[0].clips.sorted { $0.start < $1.start }
        XCTAssertEqual(clips.map(\.start),[0,150,300,600])
        XCTAssertEqual(clips.map(\.duration),[90,150,300,300])
        XCTAssertEqual(clips[1].sourceIn,5)
        XCTAssertNotEqual(clips[0].id,clips[1].id)
    }
    func testRippleRangeDeleteAcrossMultipleClips() throws {
        let p = fixture()
        let result = try TimelineCommand.deleteRange(track: p.tracks[0].id,start: 90,end: 750,ripple: true).applying(to: p)
        XCTAssertEqual(result.tracks[0].clips.map(\.start),[0,90])
        XCTAssertEqual(result.tracks[0].clips.map(\.duration),[90,150])
        XCTAssertEqual(result.tracks[0].clips[1].sourceIn,5)
        XCTAssertEqual(result.duration,240)
    }
    func testRangeDeleteOfGapDoesNotChangeSource() throws {
        var p = fixture(); p.tracks[0].clips.remove(at: 1)
        let result = try TimelineCommand.deleteRange(track: p.tracks[0].id,start: 300,end: 600,ripple: true).applying(to: p)
        XCTAssertEqual(result.tracks[0].clips.map(\.start),[0,300])
        XCTAssertEqual(result.tracks[0].clips[1].sourceIn,0)
    }
}

extension AdvancedEditingTests {
    func testMixedEditSequenceAlwaysMaintainsProjectInvariants() throws {
        var project = fixture()
        var seed: UInt64 = 0x52454E444552
        func next(_ bound: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 32) % UInt64(bound))
        }
        var selector = DeterministicSelection()
        var accepted = 0
        var rejected = 0
        for _ in 0..<400 {
            guard let clip = project.tracks[0].clips.randomElement(using: &selector) else { break }
            let delta = Int64(next(61) - 30)
            let command: TimelineCommand
            switch next(6) {
            case 0: command = .slip(clip: clip.id,delta: delta)
            case 1: command = .roll(clip: clip.id,boundary: clip.end + delta)
            case 2: command = .rippleTrim(clip: clip.id,edge: .trailing,to: clip.end + delta)
            case 3: command = .move(clips: [clip.id],delta: delta)
            case 4: command = .slide(clip: clip.id,delta: delta)
            default: command = .split(clips: [clip.id],at: clip.start + max(1,clip.duration / 2))
            }
            let original = project
            do { project = try command.applying(to: project); accepted += 1 }
            catch { XCTAssertEqual(project,original); rejected += 1 }
            try project.validate()
        }
        XCTAssertGreaterThan(accepted,50)
        XCTAssertGreaterThan(rejected,50)
    }
}

private struct DeterministicSelection: RandomNumberGenerator {
    var seed: UInt64 = 7
    mutating func next() -> UInt64 { seed = seed &* 2862933555777941757 &+ 3037000493; return seed }
}
