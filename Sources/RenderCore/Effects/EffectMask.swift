import Foundation

public struct MaskPoint: Codable, Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double,y: Double) { self.x = x; self.y = y }
}
public enum MaskShape: String, Codable, CaseIterable, Sendable { case rectangle, ellipse, polygon }
/// Source-relative coordinates, with the origin at the bottom left. No source pixels are changed.
public struct EffectMask: Codable, Equatable, Hashable, Sendable {
    public var shape: MaskShape = .ellipse
    public var x: Double = 0.5
    public var y: Double = 0.5
    public var width: Double = 0.6
    public var height: Double = 0.6
    public var feather: Double = 0.02
    public var expansion: Double = 0
    public var inverted = false
    public var points: [MaskPoint] = [.init(x: 0.1,y: 0.1),.init(x: 0.9,y: 0.1),.init(x: 0.5,y: 0.9)]
    public init() {}
    public func validate() throws {
        guard [x,y,width,height,feather,expansion].allSatisfy(\.isFinite),
              (-1...2).contains(x), (-1...2).contains(y), (0.001...4).contains(width), (0.001...4).contains(height),
              (0...0.5).contains(feather), (-0.5...0.5).contains(expansion), (3...64).contains(points.count),
              points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }) else {
            throw RenderError.invalid("Invalid effect mask geometry.")
        }
    }
}

public struct ChromaKeySettings: Codable, Equatable, Hashable, Sendable {
    public var red: Double = 0
    public var green: Double = 1
    public var blue: Double = 0
    public var softness: Double = 0.1
    public var spill: Double = 0.5
    public init() {}
    public func validate() throws {
        guard [red,green,blue,softness,spill].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            throw RenderError.invalid("Invalid chroma key settings.")
        }
    }
    /// Chroma distance ignores luminance; dark and bright variants of a screen color can key together.
    public func sample(red r: Double,green g: Double,blue b: Double,tolerance: Double) -> (Double,Double,Double,Double) {
        func chroma(_ r: Double,_ g: Double,_ b: Double) -> (Double,Double) {
            (-0.168736 * r - 0.331264 * g + 0.5 * b, 0.5 * r - 0.418688 * g - 0.081312 * b)
        }
        let c = chroma(r,g,b), key = chroma(red,green,blue)
        let distance = hypot(c.0 - key.0,c.1 - key.1)
        let t = max(0,min(1,(distance - tolerance) / max(0.001,softness)))
        let alpha = t * t * (3 - 2 * t)
        // Remove excess in the dominant screen channel near the keyed edge.
        let influence = spill * max(0,1 - max(0,distance - tolerance) / max(0.1,softness * 3))
        var output = [r,g,b]
        if green > red && green > blue { output[1] -= max(0,g - max(r,b)) * influence }
        else if blue > red && blue > green { output[2] -= max(0,b - max(r,g)) * influence }
        else if red > green && red > blue { output[0] -= max(0,r - max(g,b)) * influence }
        return (output[0] * alpha,output[1] * alpha,output[2] * alpha,alpha)
    }
}
