import Foundation

/// Half-open source seconds, independent of the sequence frame rate. Out includes the marked frame.
public struct SourceSelection: Codable, Equatable, Sendable {
    public var start: Double
    public var end: Double
    public init(start: Double,end: Double) { self.start = start; self.end = end }
    public func validate(duration: Double) throws {
        guard start.isFinite,end.isFinite,start >= 0,end > start,end <= duration + 0.000001 else { throw RenderError.invalid("Source marks must describe a non-empty range within the media.") }
    }
    public func clipFrames(at rate: FrameRate) throws -> Int64 {
        let count = floor((end - start) * rate.value + 0.0000001)
        guard count.isFinite,count >= 1,count < 100_000_000 else { throw RenderError.invalid("Select at least one complete sequence frame of source media.") }
        return Int64(count)
    }
}

extension MediaAsset {
    public func hasSamePlaybackSource(as other: MediaAsset) -> Bool {
        var a = self,b = other; a.selection = nil; b.selection = nil
        return a == b
    }
}
