import XCTest
import AVFoundation
import AppKit
import RenderCore
@testable import RenderMedia

extension MediaIntegrationTests {
    @MainActor
    func testAudioOnlyTimelineWaveformMuteAndExport() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("tone.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000,channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format,frameCapacity: 48000)!
        buffer.frameLength = 48000
        for index in 0..<48000 { buffer.floatChannelData![0][index] = Float(sin(Double(index) * 440 * 2 * .pi / 48000)) * 0.4 }
        do { let file = try AVAudioFile(forWriting: url,settings: format.settings); try file.write(from: buffer) }
        let library = MediaLibrary()
        let media = try await library.analyze(url)
        XCTAssertEqual(media.kind,.audio); XCTAssertEqual(media.audioChannels,1)
        let peaks = try await library.waveform(media)
        XCTAssertEqual(peaks.count,400); XCTAssertGreaterThan(peaks.max() ?? 0,0.3)
        var project = RenderProject(); project.settings.width = 320; project.settings.height = 180; project.assets = [media]
        var clip = TimelineClip(assetID: media.id,name: "Tone",start: 0,duration: 30)
        clip.properties.volume = 0.5
        project.tracks[1].clips = [clip]
        var config = ExportConfiguration(); config.width = 320; config.height = 180
        let output = folder.appendingPathComponent("audio.mp4")
        try await ExportService().export(project: project,configuration: config,to: output)
        let result = try await library.analyze(output)
        XCTAssertGreaterThan(result.audioChannels,0)
        let exportedPeaks = try await library.waveform(result)
        XCTAssertEqual(Double(exportedPeaks.max() ?? 0),0.2,accuracy: 0.04)
        // Repeated video+audio edits must reuse timeline tracks, not allocate one decoder track per clip.
        var sequence = RenderProject(); sequence.settings = project.settings; sequence.assets = [result]
        sequence.tracks[0].clips = Array((0..<60).map { index in
            var clip = TimelineClip(assetID: result.id,name: "Edit \(index)",start: Int64(index * 3),duration: 3)
            clip.speed = index % 2 == 0 ? 2 : 0.5
            clip.sourceIn = 0.1
            return clip
        }.reversed())
        let built = try await CompositionBuilder().build(sequence)
        let videoTracks = built.composition.tracks.filter { $0.mediaType == .video }
        let audioTracks = built.composition.tracks.filter { $0.mediaType == .audio }
        XCTAssertEqual(videoTracks.count,2) // One sequence track plus the gap/still clock.
        XCTAssertEqual(audioTracks.count,1)
        XCTAssertEqual(built.videoComposition.instructions.count,60)
        XCTAssertEqual(built.composition.duration.seconds,6,accuracy: 0.01)
        let sequenceURL = folder.appendingPathComponent("sixty-edits.mp4")
        try await ExportService().export(project: sequence,configuration: config,to: sequenceURL)
        let sequenceMedia = try await library.analyze(sequenceURL)
        XCTAssertEqual(sequenceMedia.duration,6,accuracy: 0.08)
        XCTAssertGreaterThan(sequenceMedia.audioChannels,0)
        project.tracks[1].muted = true
        let muted = try await CompositionBuilder().build(project)
        XCTAssertTrue(muted.audioMix.inputParameters.isEmpty)
    }
}
