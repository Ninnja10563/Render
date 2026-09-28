import Foundation

/// A monotonic wall-clock target lets reverse preview drop overdue frames instead of queuing seeks.
public struct ReversePreviewClock: Sendable {
    public let origin: Int64
    public let frameRate: FrameRate
    public let speed: Double
    public init(origin: Int64,frameRate: FrameRate,speed: Double) {
        self.origin = max(0,origin); self.frameRate = frameRate
        self.speed = speed.isFinite ? min(4,max(1,speed)) : 1
    }
    public func frame(elapsed: Double) -> Int64 {
        guard elapsed.isFinite, elapsed >= 0, frameRate.value.isFinite, frameRate.value > 0 else { return origin }
        let value = max(0,Double(origin) - (elapsed * frameRate.value * speed).rounded(.down))
        return value >= Double(Int64.max) ? Int64.max : Int64(value)
    }
}
