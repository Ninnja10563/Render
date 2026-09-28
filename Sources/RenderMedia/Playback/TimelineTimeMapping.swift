import Foundation
import RenderCore

/// Global seconds = origin + local seconds * scale. Local timelines may use different frame rates.
struct TimelineTimeMapping {
    var origin: Double = 0
    var scale: Double = 1
    func global(_ local: Double) -> Double { origin + local * scale }
    func local(_ global: Double) -> Double { (global - origin) / scale }
    func entering(_ clip: TimelineClip,rate: FrameRate) -> TimelineTimeMapping {
        TimelineTimeMapping(origin: global(rate.seconds(clip.start) - clip.sourceIn / clip.speed),scale: scale / clip.speed)
    }
}
struct RenderTimeWindow {
    var start: Double
    var end: Double
    func intersecting(start: Double,end: Double) -> RenderTimeWindow? {
        let lo = max(self.start,start), hi = min(self.end,end)
        return hi > lo + 0.0000001 ? RenderTimeWindow(start: lo,end: hi) : nil
    }
}
