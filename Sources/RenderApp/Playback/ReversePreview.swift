import AVFoundation
import RenderCore

extension EditorSession {
    func startReversePreview(speed: Float) {
        pause()
        guard previewReady, playhead > 0 else { return }
        transport.reversePreviewRate = speed; isPlaying = true
        let clock = ReversePreviewClock(origin: playhead,frameRate: fps,speed: Double(speed))
        let started = ProcessInfo.processInfo.systemUptime
        let item = player.currentItem
        reversePreviewTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.player.currentItem === item {
                let frame = clock.frame(elapsed: ProcessInfo.processInfo.systemUptime - started)
                if frame != self.playhead {
                    let time = CMTime(value: frame * Int64(clock.frameRate.denominator),timescale: clock.frameRate.numerator)
                    let finished = await self.player.seek(to: time,toleranceBefore: .zero,toleranceAfter: .zero)
                    guard !Task.isCancelled else { return }
                    guard finished else { self.pause(); self.previewError = "Reverse preview could not decode the requested frame."; return }
                    self.playhead = frame
                }
                if frame == 0 { self.pause(); return }
                do { try await Task.sleep(nanoseconds: 8_000_000) } catch { return }
            }
        }
    }
    func stopReversePreview() {
        reversePreviewTask?.cancel(); reversePreviewTask = nil
        transport.reversePreviewRate = 0
        player.currentItem?.cancelPendingSeeks()
    }
}
