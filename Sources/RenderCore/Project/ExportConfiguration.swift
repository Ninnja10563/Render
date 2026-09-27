import Foundation

public enum ExportCodec: String, Codable, CaseIterable, Sendable { case h264 = "H.264", hevc = "HEVC", proRes = "ProRes 422" }
public struct ExportConfiguration: Equatable, Sendable {
    public var codec: ExportCodec = .h264
    public var width: Int = 1920
    public var height: Int = 1080
    public var frameRate = FrameRate()
    public init() {}
    public func validate() throws {
        var project = RenderProject()
        project.settings.width = width; project.settings.height = height; project.settings.frameRate = frameRate
        try project.validate()
    }
}
