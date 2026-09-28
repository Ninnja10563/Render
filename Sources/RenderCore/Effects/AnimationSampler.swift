import Foundation

/// Compile once for repeated render/audio evaluation instead of sorting on every sample.
public struct AnimationSampler: Sendable {
    public let keys: [Keyframe]
    public init(_ curve: AnimationCurve) { keys = curve.keys.sorted { $0.frame < $1.frame } }
    public func value(at frame: Double,fallback: Double) -> Double {
        guard let first = keys.first, let last = keys.last else { return fallback }
        if frame <= Double(first.frame) { return first.value }
        if frame >= Double(last.frame) { return last.value }
        var lo = 0, hi = keys.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if frame < Double(keys[mid].frame) { hi = mid } else { lo = mid }
        }
        let a = keys[lo], b = keys[hi]
        let t = (frame - Double(a.frame)) / Double(max(1,b.frame - a.frame))
        let u: Double
        switch a.interpolation {
        case .linear: u = t
        case .hold: u = 0
        case .easeIn: u = t * t
        case .easeOut: u = 1 - (1 - t) * (1 - t)
        case .easeInOut: u = t * t * (3 - 2 * t)
        }
        return a.value + (b.value - a.value) * u
    }
}
