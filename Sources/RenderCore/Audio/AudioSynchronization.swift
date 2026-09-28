import Foundation

public struct AudioSyncMatch: Equatable, Sendable {
    /// Target sample zero aligns with this index in the reference signal.
    public let offset: Int
    public let correlation: Double
    public let separation: Double
}

public enum AudioSynchronization {
    /// Normalized envelope correlation. Coarse search followed by full-resolution refinement.
    /// Inputs are fixed-rate amplitude envelopes, not display waveform bins.
    public static func match(reference: [Float], target: [Float], maximumOffset: Int, minimumOverlap: Int) throws -> AudioSyncMatch {
        guard reference.count >= minimumOverlap, target.count >= minimumOverlap, minimumOverlap >= 100,
              reference.count <= 12000, target.count <= 12000, (0...3000).contains(maximumOffset),
              reference.allSatisfy({ $0.isFinite }), target.allSatisfy({ $0.isFinite }) else { throw RenderError.invalid("Audio synchronization needs at least one second of valid audio.") }
        func score(_ lag: Int, stride step: Int) -> Double {
            let start = max(0,lag), end = min(reference.count,target.count + lag)
            guard end - start >= minimumOverlap else { return -1 }
            var x = 0.0, y = 0.0, xx = 0.0, yy = 0.0, xy = 0.0, count = 0.0
            for index in Swift.stride(from: start,to: end,by: step) {
                let a = Double(reference[index]), b = Double(target[index - lag])
                x += a; y += b; xx += a * a; yy += b * b; xy += a * b; count += 1
            }
            let vx = xx - x * x / count, vy = yy - y * y / count
            guard vx / count > 1e-8, vy / count > 1e-8 else { return -1 }
            return (xy - x * y / count) / sqrt(vx * vy)
        }
        var candidates: [(lag: Int,score: Double)] = []
        for lag in Swift.stride(from: -maximumOffset,through: maximumOffset,by: 1) {
            try Task.checkCancellation()
            candidates.append((lag,score(lag,stride: 5)))
        }
        // Refine several peaks so coarse sampling does not choose a narrow false peak.
        let ranked = candidates.sorted { $0.score > $1.score }
        var peaks: [Int] = []
        for candidate in ranked where !peaks.contains(where: { abs($0 - candidate.lag) <= 10 }) {
            peaks.append(candidate.lag); if peaks.count == 8 { break }
        }
        var refined: [Int: Double] = [:]
        for peak in peaks {
            for lag in max(-maximumOffset,peak - 5)...min(maximumOffset,peak + 5) {
                try Task.checkCancellation(); refined[lag] = score(lag,stride: 1)
            }
        }
        guard let best = refined.max(by: { $0.value < $1.value }) else { throw RenderError.invalid("No overlapping audio was found.") }
        let alternative = refined.filter { abs($0.key - best.key) > 10 }.map(\.value).max() ?? -1
        let separation = best.value - alternative
        guard best.value >= 0.65, separation >= 0.04 else { throw RenderError.invalid("The audio match is ambiguous. Choose clips with clearer shared sound, or align them manually.") }
        return AudioSyncMatch(offset: best.key,correlation: min(1,best.value),separation: separation)
    }
}
