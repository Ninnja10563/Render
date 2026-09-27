import Foundation

public struct AudioAutomationRamp: Equatable, Sendable {
    public let start: Int64
    public let end: Int64
    public let from: Double
    public let to: Double
}

public enum AudioAutomation {
    /// Constant/linear/hold segments are exact. Ease segments use at most 64 subdivisions
    /// per keyframe interval, avoiding a ramp allocation for every frame of a long clip.
    public static func ramps(curve: AnimationCurve, offset: Int64, duration: Int64, fallback: Double) -> [AudioAutomationRamp] {
        guard duration > 0 else { return [] }
        let keys = curve.keys.sorted { $0.frame < $1.frame }
        let end = offset + duration
        let boundaries = ([offset,end] + keys.map(\.frame).filter { $0 > offset && $0 < end }).sorted()
        var result: [AudioAutomationRamp] = []
        for (a,b) in zip(boundaries,boundaries.dropFirst()) {
            let interpolation = keys.last(where: { $0.frame <= a })?.interpolation ?? .hold
            let from = curve.value(at: Double(a),fallback: fallback)
            let to = interpolation == .hold ? from : curve.value(at: Double(b),fallback: fallback)
            let subdivisions: Int64
            switch interpolation {
            case .easeIn,.easeOut,.easeInOut: subdivisions = from == to ? 1 : min(64,b - a)
            default: subdivisions = 1
            }
            if subdivisions == 1 {
                result.append(AudioAutomationRamp(start: a - offset,end: b - offset,from: from,to: to))
            } else {
                for part in 0..<subdivisions {
                    let lo = a + (b - a) * part / subdivisions
                    let hi = a + (b - a) * (part + 1) / subdivisions
                    result.append(AudioAutomationRamp(start: lo - offset,end: hi - offset,
                                                      from: curve.value(at: Double(lo),fallback: fallback),
                                                      to: curve.value(at: Double(hi),fallback: fallback)))
                }
            }
        }
        return result
    }
}
