import Foundation

public enum BlendMode: String, Codable, CaseIterable, Sendable {
    case normal, multiply, screen, overlay, add, darken, lighten
    public var label: String { rawValue.capitalized }
}
public struct ClipGeometry: Codable, Equatable, Sendable {
    public var scaleX: Double = 1
    public var scaleY: Double = 1
    public var anchorX: Double = 0.5
    public var anchorY: Double = 0.5
    public var cropLeft: Double = 0
    public var cropRight: Double = 0
    public var cropTop: Double = 0
    public var cropBottom: Double = 0
    public var flipHorizontal = false
    public var flipVertical = false
    public var blend: BlendMode = .normal
    public init() {}
    public func validate() throws {
        guard [scaleX,scaleY,anchorX,anchorY,cropLeft,cropRight,cropTop,cropBottom].allSatisfy(\.isFinite),
              (0.01...10).contains(scaleX), (0.01...10).contains(scaleY),
              (0...1).contains(anchorX), (0...1).contains(anchorY),
              [cropLeft,cropRight,cropTop,cropBottom].allSatisfy({ (0...1).contains($0) }) else { throw RenderError.invalid("Invalid crop or transform geometry.") }
    }
}

extension ClipProperties {
    public static let animationRanges: [String: ClosedRange<Double>] = [
        "x": -32768...32768,"y": -32768...32768,"scale": 0.01...10,"rotation": -3600...3600,
        "opacity": 0...1,"volume": 0...4,"scaleX": 0.01...10,"scaleY": 0.01...10,
        "anchorX": 0...1,"anchorY": 0...1,"cropLeft": 0...1,"cropRight": 0...1,"cropTop": 0...1,"cropBottom": 0...1
    ]
    public mutating func setBaseValue(_ key: String,value: Double) throws {
        guard value.isFinite, let range = Self.animationRanges[key], range.contains(value) else { throw RenderError.invalid("Property value is outside its supported range.") }
        switch key {
        case "x": x = value
        case "y": y = value
        case "scale": scale = value
        case "rotation": rotation = value
        case "opacity": opacity = value
        case "volume": volume = value
        default:
            var next = geometry ?? ClipGeometry()
            switch key {
            case "scaleX": next.scaleX = value
            case "scaleY": next.scaleY = value
            case "anchorX": next.anchorX = value
            case "anchorY": next.anchorY = value
            case "cropLeft": next.cropLeft = value
            case "cropRight": next.cropRight = value
            case "cropTop": next.cropTop = value
            case "cropBottom": next.cropBottom = value
            default: break
            }
            geometry = next
        }
    }
}
