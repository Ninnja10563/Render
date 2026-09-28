import AVFoundation
import RenderCore

extension EditorSession {
    func checkReversePreview() async throws {
        guard previewReady, project.duration > 60 else { throw RenderError.invalid("Reverse validation requires a prepared timeline.") }
        pause(); seek(60)
        try await Task.sleep(nanoseconds: 80_000_000)
        startReversePreview(speed: 1)
        let deadline = Date().addingTimeInterval(2)
        while playhead > 54 {
            if let error = previewError { throw RenderError.invalid(error) }
            guard Date() < deadline else { throw RenderError.invalid("Reverse preview did not advance continuously.") }
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        guard isPlaying, transport.reversePreviewRate == 1 else { throw RenderError.invalid("Reverse transport state desynchronized.") }
        pause(); let stopped = playhead
        try await Task.sleep(nanoseconds: 150_000_000)
        guard playhead == stopped, !isPlaying else { throw RenderError.invalid("Reverse preview continued after pause.") }
        startReversePreview(speed: 2); seek(45)
        try await Task.sleep(nanoseconds: 100_000_000)
        guard playhead == 45, transport.reversePreviewRate == 0 else { throw RenderError.invalid("Scrubbing did not cancel reverse seeks.") }
        startReversePreview(speed: 1); shuttle(1)
        guard transport.reversePreviewRate == 0, player.rate > 0 else { throw RenderError.invalid("Forward playback did not replace reverse preview.") }
        pause(); seek(2); startReversePreview(speed: 4)
        let end = Date().addingTimeInterval(2)
        while isPlaying {
            guard Date() < end else { throw RenderError.invalid("Reverse preview did not stop at the beginning.") }
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        guard playhead == 0 else { throw RenderError.invalid("Reverse preview stopped at the wrong frame.") }
        print("RENDER_REVERSE_OK continuous seek-cancellation pause forward beginning")
    }
}
