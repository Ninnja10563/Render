import Foundation

public struct FrameRate: Codable, Hashable, Sendable {
    public var numerator: Int32
    public var denominator: Int32
    public init(_ numerator: Int32 = 30, _ denominator: Int32 = 1) {
        self.numerator = numerator; self.denominator = denominator
    }
    public var value: Double { Double(numerator) / Double(denominator) }
    public func seconds(_ frames: Int64) -> Double { Double(frames) / value }
    public func frames(_ seconds: Double) -> Int64 { Int64((seconds * value).rounded()) }
    /// Validate user-entered timeline times before converting floating point to integer frames.
    public func editingFrames(_ seconds: Double) throws -> Int64 {
        let frames = (seconds * value).rounded()
        guard numerator > 0, denominator > 0, seconds.isFinite, frames.isFinite, frames >= 0, frames < 100_000_000 else {
            throw RenderError.invalid("Time is outside the supported timeline range.")
        }
        return Int64(frames)
    }
    /// Non-drop-frame timecode; the rational rate is retained for media timing.
    public func timecode(_ frame: Int64) -> String {
        let nominal = max(1, Int64(value.rounded()))
        let f = max(0, frame)
        return String(format: "%02lld:%02lld:%02lld:%02lld", f / nominal / 3600, f / nominal / 60 % 60, f / nominal % 60, f % nominal)
    }
}

public enum RenderError: LocalizedError, Equatable {
    case invalid(String)
    case missingMedia(String)
    case unsupportedVersion(Int)
    public var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        case .missingMedia(let name): return "Missing media: \(name). Locate the original using Relink Media."
        case .unsupportedVersion(let version): return "This project uses format \(version), which this version of Render cannot open."
        }
    }
}
