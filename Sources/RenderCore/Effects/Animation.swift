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
    case exposure, brightness, contrast, saturation, gaussianBlur, sharpen, vignette, highlights, shadows, temperature, tint, chromaKey, opacity
    public var label: String {
        switch self {
        case .highlights: return "Highlights"
        case .shadows: return "Shadows"
        case .temperature: return "Temperature"
        case .tint: return "Tint"
        case .chromaKey: return "Chroma Key"
        case .opacity: return "Opacity"
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
        case .highlights, .shadows, .chromaKey, .opacity: return 0...1
        case .temperature: return 2000...12000
        case .tint: return -150...150
        case .exposure: return -4...4
        case .brightness: return -1...1
        case .contrast, .saturation: return 0...2
        case .gaussianBlur: return 0...50
        case .sharpen, .vignette: return 0...2
        }
    }
    public var defaultValue: Double {
        switch self { case .temperature: return 6500; case .chromaKey: return 0.15; case .highlights, .contrast, .saturation: return 1; case .gaussianBlur: return 5; case .sharpen, .vignette: return 0.5; default: return 0 }
    }
}
public struct Effect: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var kind: EffectKind
    public var enabled = true
    public var amount: Double
    public var mask: EffectMask?
    public var keying: ChromaKeySettings?
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
    public var geometry: ClipGeometry?
    public var audioFades: ClipAudioFades?
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
        case "scaleX": fallback = geometry?.scaleX ?? 1
        case "scaleY": fallback = geometry?.scaleY ?? 1
        case "anchorX": fallback = geometry?.anchorX ?? 0.5
        case "anchorY": fallback = geometry?.anchorY ?? 0.5
        case "cropLeft": fallback = geometry?.cropLeft ?? 0
        case "cropRight": fallback = geometry?.cropRight ?? 0
        case "cropTop": fallback = geometry?.cropTop ?? 0
        case "cropBottom": fallback = geometry?.cropBottom ?? 0
        default: fallback = 0
        }
        return animations[property]?.value(at: frame, fallback: fallback) ?? fallback
    }
}
