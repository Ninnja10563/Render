import XCTest
import AVFoundation
import AppKit
import RenderCore
@testable import RenderMedia

extension MediaIntegrationTests {
    @MainActor
    func testCompoundRetimingUsesChildFrameRateAndCanvasInPreviewAndExport() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = MediaLibrary()
        let red = try await library.analyze(makeImage(in: folder)), blue = try await library.analyze(makeImage(in: folder,name: "blue.png",color: .blue))
        var project = RenderProject(); project.settings.width = 320; project.settings.height = 180; project.assets = [red,blue]
        var settings = ProjectSettings(); settings.width = 160; settings.height = 160; settings.frameRate = FrameRate(24)
        var track = TimelineTrack(name: "Nested",kind: .video)
        track.clips = [TimelineClip(assetID: red.id,name: "Red",start: 0,duration: 24),TimelineClip(assetID: blue.id,name: "Blue",start: 24,duration: 72)]
        let source = CompoundSource(name: "Square 24",kind: .video,settings: settings,duration: 96,tracks: [track])
        var parent = TimelineClip(assetID: nil,name: source.name,start: 15,duration: 45)
        parent.compoundID = source.id; parent.sourceIn = 0.5; parent.speed = 2; parent.properties.opacity = 0.5
        project.compounds = [source]; project.tracks[0].clips = [parent]
        let prepared = try await CompositionBuilder().build(project)
        let preview = AVAssetImageGenerator(asset: prepared.composition); preview.videoComposition = prepared.videoComposition
        preview.requestedTimeToleranceBefore = .zero; preview.requestedTimeToleranceAfter = .zero
        var config = ExportConfiguration(); config.width = 320; config.height = 180; config.quality = .balanced
        let url = folder.appendingPathComponent("nested.mp4")
        try await ExportService().export(project: project,configuration: config,to: url)
        let encoded = AVAssetImageGenerator(asset: AVURLAsset(url: url)); encoded.requestedTimeToleranceBefore = .zero; encoded.requestedTimeToleranceAfter = .zero
        for (frame,channel) in [(16,0),(25,2),(59,2)] {
            let timestamp = CMTime(value: Int64(frame),timescale: 30)
            let previewImage = try await preview.image(at: timestamp).image
            let encodedImage = try await encoded.image(at: timestamp).image
            let center = CGRect(x: 150,y: 80,width: 20,height: 20)
            let a = pixel(try XCTUnwrap(previewImage.cropping(to: center))), b = pixel(try XCTUnwrap(encodedImage.cropping(to: center)))
            let edge = pixel(try XCTUnwrap(previewImage.cropping(to: CGRect(x: 5,y: 80,width: 10,height: 10))))
            XCTAssertLessThan(edge[0],5); XCTAssertLessThan(edge[2],5,"Child square canvas stays letterboxed")
            XCTAssertGreaterThan(a[channel],120); XCTAssertLessThan(a[channel],220)
            XCTAssertLessThan(a[channel == 0 ? 2 : 0],10)
            for c in 0..<3 { XCTAssertEqual(Double(a[c]),Double(b[c]),accuracy: 15) }
        }
        let instructions = prepared.videoComposition.instructions.compactMap { $0 as? RenderInstruction }
        XCTAssertEqual(instructions.count,3)
        XCTAssertEqual(instructions.first?.nodes.count,0)
        XCTAssertEqual(instructions.last?.nodes.first?.clip.id == parent.id,false,"Runtime instances receive unique render identities")
    }

    @MainActor
    func testCompoundAudioMultipliesParentHoldAutomationAndChildFades() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("tone.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000,channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format,frameCapacity: 96000)!; buffer.frameLength = 96000
        for i in 0..<96000 { buffer.floatChannelData![0][i] = Float(sin(Double(i) * 440 * 2 * .pi / 48000)) * 0.4 }
        do { let file = try AVAudioFile(forWriting: source,settings: format.settings); try file.write(from: buffer) }
        let library = MediaLibrary(), media = try await library.analyze(source)
        var project = RenderProject(); project.settings.width = 320; project.settings.height = 180; project.assets = [media]
        var clip = TimelineClip(assetID: media.id,name: "Tone",start: 0,duration: 60)
        clip.properties.volume = 0.5; clip.properties.audioFades = ClipAudioFades(start: 0,end: 60,fadeIn: 30,fadeOut: 0)
        project.tracks[1].clips = [clip]
        project = try CompoundEditing.create([clip.id],name: "Inner",in: project)
        let inner = project.tracks.flatMap(\.clips).first!
        project = try CompoundEditing.create([inner.id],name: "Outer",in: project)
        let parent = project.tracks.flatMap(\.clips).first!
        var properties = parent.properties
        properties.animations["volume"] = AnimationCurve(keys: [Keyframe(frame: 0,value: 0.5,interpolation: .hold),Keyframe(frame: 30,value: 1)])
        project = try TimelineCommand.properties(clip: parent.id,properties).applying(to: project)
        let url = folder.appendingPathComponent("compound-audio.mp4")
        var config = ExportConfiguration(); config.width = 320; config.height = 180
        try await ExportService().export(project: project,configuration: config,to: url)
        let peaks = try await library.waveform(try await library.analyze(url),bins: 120)
        for bin in [15,30,45,75,90,105] {
            let frame = (Double(bin) + 0.5) / 2
            let expected = 0.2 * (frame < 30 ? 0.5 : 1) * clip.properties.audioFades!.gain(at: frame)
            XCTAssertEqual(Double(peaks[bin]),expected,accuracy: 0.025,"Frame \(frame)")
        }
        let prepared = try await CompositionBuilder().build(project)
        XCTAssertEqual(prepared.audioMix.inputParameters.count,1)
        var muted = project; muted.tracks[try XCTUnwrap(muted.location(parent.id)).track].muted = true
        let silent = try await CompositionBuilder().build(muted)
        XCTAssertEqual(silent.audioMix.inputParameters.count,0)
    }

    func testNestedAudioClockAndHoldLeftLimits() {
        var parent = TimelineClip(assetID: nil,name: "Parent",start: 30,duration: 60); parent.sourceIn = 0.5; parent.speed = 2
        let childMapping = TimelineTimeMapping().entering(parent,rate: FrameRate())
        XCTAssertEqual(childMapping.global(0.5),1,accuracy: 1e-10)
        XCTAssertEqual(childMapping.global(1.5),1.5,accuracy: 1e-10)
        var child = TimelineClip(assetID: nil,name: "Child",start: 12,duration: 48)
        child.properties.animations["volume"] = AnimationCurve(keys: [Keyframe(frame: 0,value: 0.2,interpolation: .hold),Keyframe(frame: 24,value: 0.8)])
        let envelope = CompoundAudioEnvelope(clip: child,rate: FrameRate(24),mapping: childMapping,incoming: nil,outgoing: nil)
        XCTAssertEqual(envelope.gain(at: 1.499),0.2,accuracy: 1e-9)
        XCTAssertEqual(envelope.gain(at: 1.5),0.8,accuracy: 1e-9)
        XCTAssertTrue(envelope.boundaries.contains(1.5))
    }
}
