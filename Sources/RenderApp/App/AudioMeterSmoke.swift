import AVFoundation
import RenderCore

extension EditorSession {
    func checkAudioMeterPlayback(folder: URL) async throws {
        let source = folder.appendingPathComponent("Meter playback.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000,channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format,frameCapacity: 144000)!; buffer.frameLength = 144000
        for frame in 0..<144000 {
            let wave = Float(sin(Double(frame) * 440 * 2 * .pi / 48000))
            buffer.floatChannelData![0][frame] = wave * 0.2; buffer.floatChannelData![1][frame] = wave * 0.1
        }
        do { let file = try AVAudioFile(forWriting: source,settings: format.settings); try file.write(from: buffer) }
        let asset = try await library.analyze(source)
        let editor = EditorSession()
        var fixture = RenderProject(); fixture.settings.width = 320; fixture.settings.height = 180; fixture.assets = [asset]
        var clip = TimelineClip(assetID: asset.id,name: "Meter tone",start: 0,duration: 90); clip.properties.volume = 0.5
        fixture.tracks[1].clips = [clip]
        editor.commit(fixture,name: "Meter fixture")
        let ready = Date().addingTimeInterval(8)
        while !editor.previewReady || editor.player.currentItem?.status != .readyToPlay {
            if let error = editor.previewError { throw RenderError.invalid(error) }
            guard Date() < ready else { throw RenderError.invalid("Audio meter playback did not become ready.") }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        editor.togglePlayback()
        defer { editor.pause() }
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if let reading = editor.audioMeters.inputs.first, reading.peaks.count == 2, reading.peaks[0] > 0.08 {
                guard reading.peaks[0] < 0.12, reading.peaks[1] > 0.035, reading.peaks[1] < 0.065 else { throw RenderError.invalid("Playback meter does not reflect post-volume channels.") }
                editor.pause()
                guard editor.audioMeters.inputs.first?.peaks.allSatisfy({ $0 == 0 }) == true else { throw RenderError.invalid("Pause did not clear meter levels.") }
                perform(.addAsset(asset)); append(asset.id); loadPreview(asset)
                print("RENDER_AUDIO_METER_OK real-playback stereo post-fader clock-alignment pause")
                return
            }
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        throw RenderError.invalid("Audio playback produced no measured input samples.")
    }
}
