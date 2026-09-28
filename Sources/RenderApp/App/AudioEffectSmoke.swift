import AVFoundation
import RenderCore

extension EditorSession {
    func checkAudioEffectPlayback(folder: URL) async throws {
        let asset = try await library.analyze(folder.appendingPathComponent("Meter playback.wav"))
        let editor = EditorSession()
        var fixture = RenderProject(); fixture.settings.width = 320; fixture.settings.height = 180; fixture.assets = [asset]
        let clip = TimelineClip(assetID: asset.id,name: "Processed tone",start: 0,duration: 90)
        fixture.tracks[1].clips = [clip]; editor.commit(fixture,name: "Audio effect fixture")
        var properties = clip.properties, effect = AudioEffect(kind: .limiter)
        effect.values["ceiling"] = -20; properties.audioEffects = [effect]
        editor.perform(.properties(clip: clip.id,properties))
        let restored = try JSONDecoder().decode(RenderProject.self,from: JSONEncoder().encode(editor.document))
        guard restored == editor.document else { throw RenderError.invalid("Audio effects did not survive project serialization.") }
        let ready = Date().addingTimeInterval(8)
        while !editor.previewReady || editor.player.currentItem?.status != .readyToPlay {
            if let error = editor.previewError { throw RenderError.invalid(error) }
            guard Date() < ready else { throw RenderError.invalid("Audio effect playback did not become ready.") }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        editor.togglePlayback(); defer { editor.pause() }
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if let reading = editor.audioMeters.inputs.first,reading.peaks.count == 2,reading.peaks[0] > 0.08 {
                guard reading.peaks[0] <= 0.102,abs(reading.peaks[1] - reading.peaks[0] * 0.5) < 0.003 else { throw RenderError.invalid("Audio processor playback samples differ from the linked limiter output.") }
                editor.pause(); editor.undo()
                guard editor.project.tracks[1].clips[0].properties.audioEffects == nil else { throw RenderError.invalid("Undo did not remove the audio effect stack.") }
                editor.redo()
                guard editor.project.tracks[1].clips[0].properties.audioEffects == [effect] else { throw RenderError.invalid("Redo did not restore audio processors.") }
                print("RENDER_AUDIO_EFFECT_OK real-playback stereo limiter undo redo serialization")
                return
            }
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        throw RenderError.invalid("Audio effect playback produced no measured samples.")
    }
}
