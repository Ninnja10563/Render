import XCTest
import AVFoundation
import RenderCore
@testable import RenderMedia

extension MediaIntegrationTests {
    @MainActor
    func testExportedFadeShapesAndSplitHaveMatchingLevels() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("fade-tone.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000,channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format,frameCapacity: 96000)!
        buffer.frameLength = 96000
        for index in 0..<96000 { buffer.floatChannelData![0][index] = Float(sin(Double(index) * 440 * 2 * .pi / 48000)) * 0.4 }
        do { let file = try AVAudioFile(forWriting: source,settings: format.settings); try file.write(from: buffer) }
        let library = MediaLibrary(), media = try await library.analyze(source)
        var project = RenderProject(); project.settings.width = 320; project.settings.height = 180; project.assets = [media]
        var clip = TimelineClip(assetID: media.id,name: "Fade",start: 0,duration: 60)
        var config = ExportConfiguration(); config.width = 320; config.height = 180
        for shape in AudioFadeShape.allCases {
            clip.properties.audioFades = ClipAudioFades(start: 0,end: 60,fadeIn: 30,fadeOut: 30,shape: shape)
            project.tracks[1].clips = [clip]
            let split = try TimelineCommand.split(clips: [clip.id],at: 15).applying(to: project)
            var reference: [Float] = []
            for (index,edit) in [project,split].enumerated() {
                let output = folder.appendingPathComponent("\(shape.rawValue)-\(index).mp4")
                try await ExportService().export(project: edit,configuration: config,to: output)
                let result = try await library.analyze(output)
                let peaks = try await library.waveform(result,bins: 120)
                for bin in [15,30,45,75,90,105] {
                    let time = (Double(bin) + 0.5) / 2
                    XCTAssertEqual(Double(peaks[bin]),0.4 * clip.properties.audioFades!.gain(at: time),accuracy: 0.035,"\(shape) bin \(bin)")
                }
                if index == 0 { reference = peaks }
                else { for bin in 5..<115 { XCTAssertEqual(peaks[bin],reference[bin],accuracy: 0.02) } }
            }
        }
    }
}
