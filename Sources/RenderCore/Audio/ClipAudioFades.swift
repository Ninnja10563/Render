import Foundation

public enum AudioFadeShape: String, Codable, CaseIterable, Sendable {
    case linear, smooth, equalPower
    public var label: String {
        switch self { case .linear: return "Linear"; case .smooth: return "Smooth"; case .equalPower: return "Equal Power" }
    }
    public func value(_ progress: Double) -> Double {
        let t = min(1,max(0,progress))
        switch self { case .linear: return t; case .smooth: return t * t * (3 - 2 * t); case .equalPower: return sin(t * .pi / 2) }
    }
}

/// Frames share the volume animation coordinate system, so splitting never restarts a fade.
public struct ClipAudioFades: Codable, Equatable, Sendable {
    public var start: Int64
    public var end: Int64
    public var fadeIn: Int64
    public var fadeOut: Int64
    public var shape: AudioFadeShape
    public init(start: Int64, end: Int64, fadeIn: Int64 = 0, fadeOut: Int64 = 0, shape: AudioFadeShape = .linear) {
        self.start = start; self.end = end; self.fadeIn = fadeIn; self.fadeOut = fadeOut; self.shape = shape
    }
    public func validate() throws {
        guard start >= 0, end > start, end < 200_000_000, fadeIn >= 0, fadeOut >= 0,
              fadeIn <= end - start, fadeOut <= end - start else { throw RenderError.invalid("Invalid audio fade duration.") }
    }
    public func gain(at frame: Double) -> Double {
        let incoming = fadeIn > 0 ? shape.value((frame - Double(start)) / Double(fadeIn)) : 1
        let outgoing = fadeOut > 0 ? shape.value((Double(end) - frame) / Double(fadeOut)) : 1
        return incoming * outgoing
    }
}

extension AudioAutomation {
    /// Sample only changing fade intervals, with bounded work regardless of sequence duration.
    public static func applying(_ fades: ClipAudioFades?, to ramps: [AudioAutomationRamp], offset: Int64) -> [AudioAutomationRamp] {
        guard let fades, fades.fadeIn > 0 || fades.fadeOut > 0 else { return ramps }
        let points = [fades.start,fades.start + fades.fadeIn,fades.end - fades.fadeOut,fades.end].map { $0 - offset }
        var result: [AudioAutomationRamp] = []
        for ramp in ramps {
            let boundaries = Set([ramp.start,ramp.end] + points.filter { $0 > ramp.start && $0 < ramp.end }).sorted()
            func gain(_ frame: Int64) -> Double {
                let t = Double(frame - ramp.start) / Double(max(1,ramp.end - ramp.start))
                return (ramp.from + (ramp.to - ramp.from) * t) * fades.gain(at: Double(frame + offset))
            }
            for (a,b) in zip(boundaries,boundaries.dropFirst()) {
                let mid = Double(a + b) / 2 + Double(offset)
                let changing = (fades.fadeIn > 0 && mid > Double(fades.start) && mid < Double(fades.start + fades.fadeIn)) ||
                    (fades.fadeOut > 0 && mid > Double(fades.end - fades.fadeOut) && mid < Double(fades.end))
                let parts = changing ? min(Int64(128),b - a) : 1
                for index in 0..<parts {
                    let lo = a + (b - a) * index / parts, hi = a + (b - a) * (index + 1) / parts
                    result.append(AudioAutomationRamp(start: lo,end: hi,from: gain(lo),to: gain(hi)))
                }
            }
        }
        return result
    }
}
