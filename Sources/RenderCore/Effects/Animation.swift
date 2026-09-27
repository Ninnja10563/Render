import Foundation

public enum Interpolation: String, Codable, CaseIterable, Sendable { case linear, easeIn, easeOut, easeInOut, hold }
public struct Keyframe: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var frame: Int64
    public var value: Double
    public var interpolation: Interpolation
    public init(frame: Int64, value: Double, interpolation: Interpolation = .linear) {
        self.frame = frame; self.value = value; self.interpolation = interpolation
    }
}
public struct AnimationCurve: Codable, Equatable, Sendable {
    public var keys: [Keyframe] = []
    public init(keys: [Keyframe] = []) { self.keys = keys }
    public mutating func set(_ key: Keyframe) {
        keys.removeAll { $0.frame == key.frame || $0.id == key.id }
        keys.append(key); keys.sort { $0.frame < $1.frame }
    }
    public func value(at frame: Double, fallback: Double) -> Double {
        let sorted = keys.sorted { $0.frame < $1.frame }
        guard let first = sorted.first, let last = sorted.last else { return fallback }
        if frame <= Double(first.frame) { return first.value }
        if frame >= Double(last.frame) { return last.value }
        for (a, b) in zip(sorted, sorted.dropFirst()) where frame < Double(b.frame) {
            let t = (frame - Double(a.frame)) / Double(b.frame - a.frame)
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
        return last.value
    }
}

public enum EffectKind: String, Codable, CaseIterable, Sendable {
    case exposure, brightness, contrast, saturation, gaussianBlur, sharpen, vignette
    public var label: String {
        switch self {
        case .exposure: return "Exposure"
        case .brightness: return "Brightness"
        case .contrast: return "Contrast"
        case .saturation: return "Saturation"
        case .gaussianBlur: return "Gaussian Blur"
        case .sharpen: return "Sharpen"
        case .vignette: return "Vignette"
        }
    }
    public var range: ClosedRange<Double> {
        switch self {
        case .exposure: return -4...4
        case .brightness: return -1...1
        case .contrast, .saturation: return 0...2
        case .gaussianBlur: return 0...50
        case .sharpen, .vignette: return 0...2
        }
    }
    public var defaultValue: Double {
        switch self { case .contrast, .saturation: return 1; case .gaussianBlur: return 5; case .sharpen, .vignette: return 0.5; default: return 0 }
    }
}
public struct Effect: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var kind: EffectKind
    public var enabled = true
    public var amount: Double
    public var animation = AnimationCurve()
    public init(kind: EffectKind) { self.kind = kind; amount = kind.defaultValue }
}
public struct ClipProperties: Codable, Equatable, Sendable {
    public var x: Double = 0
    public var y: Double = 0
    public var scale: Double = 1
    public var rotation: Double = 0
    public var opacity: Double = 1
    public var volume: Double = 1
    public var muted = false
    public var animations: [String: AnimationCurve] = [:]
    public init() {}
    public func value(_ property: String, at frame: Double) -> Double {
        let fallback: Double
        switch property {
        case "x": fallback = x
        case "y": fallback = y
        case "scale": fallback = scale
        case "rotation": fallback = rotation
        case "opacity": fallback = opacity
        case "volume": fallback = volume
        default: fallback = 0
        }
        return animations[property]?.value(at: frame, fallback: fallback) ?? fallback
    }
}
