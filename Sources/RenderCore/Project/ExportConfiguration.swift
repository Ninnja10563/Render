import Foundation

public enum ExportCodec: String, Codable, CaseIterable, Sendable { case h264 = "H.264", hevc = "HEVC", proRes = "ProRes 422" }
public enum ExportQuality: String, CaseIterable, Sendable {
    case automatic = "Codec Managed", compact = "Compact", balanced = "Balanced", high = "High", custom = "Custom Bitrate"
}
public struct ExportConfiguration: Equatable, Sendable {
    public var codec: ExportCodec = .h264
    public var width: Int = 1920
    public var height: Int = 1080
    public var frameRate = FrameRate()
    public var quality: ExportQuality = .automatic
    public var customBitrateMbps: Double = 20
    public var videoBitrate: Int? {
        guard codec != .proRes, quality != .automatic else { return nil }
        if quality == .custom { return customBitrateMbps.isFinite && (0.5...200).contains(customBitrateMbps) ? Int(customBitrateMbps * 1_000_000) : nil }
        let factor = quality == .compact ? 0.08 : quality == .balanced ? 0.15 : 0.3
        let rate = Double(width) * Double(height) * frameRate.value * factor * (codec == .hevc ? 0.65 : 1)
        guard rate.isFinite else { return nil }
        return Int(min(200_000_000,max(500_000,rate)))
    }
    public func estimatedBytes(duration: Double) -> Double? {
        guard let bitrate = videoBitrate, duration.isFinite, duration >= 0 else { return nil }
        return duration * Double(bitrate + 320_000) / 8
    }
    public init() {}
    public func validate() throws {
        guard codec != .proRes || quality == .automatic else { throw RenderError.invalid("ProRes uses codec-managed quality.") }
        guard quality != .custom || (customBitrateMbps.isFinite && (0.5...200).contains(customBitrateMbps)) else { throw RenderError.invalid("Video bitrate must be between 0.5 and 200 Mbps.") }
        var project = RenderProject()
        project.settings.width = width; project.settings.height = height; project.settings.frameRate = frameRate
        try project.validate()
    }
}
