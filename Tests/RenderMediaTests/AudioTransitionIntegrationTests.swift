import XCTest
import AVFoundation
import RenderCore
@testable import RenderMedia

extension MediaIntegrationTests {
    @MainActor
    func testAudioCrossfadeKeepsAlignedToneLevel() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("tone.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000,channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format,frameCapacity: 48000)!
        buffer.frameLength = 48000
        for index in 0..<48000 { buffer.floatChannelData![0][index] = Float(sin(Double(index) * 440 * 2 * .pi / 48000)) * 0.2 }
        do { let file = try AVAudioFile(forWriting: source,settings: format.settings); try file.write(from: buffer) }
        let library = MediaLibrary(), media = try await library.analyze(source)
        var project = RenderProject(); project.settings.width = 320; project.settings.height = 180; project.assets = [media]
        project.tracks[1].clips = [TimelineClip(assetID: media.id,name: "Tone",start: 0,duration: 30)]
        var config = ExportConfiguration(); config.width = 320; config.height = 180
        let encodedSource = folder.appendingPathComponent("source.mp4")
        try await ExportService().export(project: project,configuration: config,to: encodedSource)
        let video = try await library.analyze(encodedSource)
        project.assets = [video]; project.tracks[1].clips = []
        var left = TimelineClip(assetID: video.id,name: "Left",start: 0,duration: 6); left.sourceIn = 0.1
        var right = TimelineClip(assetID: video.id,name: "Right",start: 6,duration: 6); right.sourceIn = 0.1
        left.transition = ClipTransition(rightID: right.id,kind: .crossDissolve,duration: 6)
        project.tracks[0].clips = [left,right]
        let built = try await CompositionBuilder().build(project)
        XCTAssertEqual(built.composition.tracks.filter { $0.mediaType == .audio }.count,2)
        XCTAssertEqual(built.audioMix.inputParameters.count,2)
        let output = folder.appendingPathComponent("crossfade.mp4")
        try await ExportService().export(project: project,configuration: config,to: output)
        let result = try await library.analyze(output)
        let peaks = try await library.waveform(result,bins: 80)
        let mean = peaks[30..<50].reduce(0,+) / 20
        XCTAssertEqual(Double(mean),0.2,accuracy: 0.045)
    }
}
