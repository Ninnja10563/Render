import AVFoundation
import CoreImage
import RenderCore

struct RenderLayer {
    var trackID: CMPersistentTrackID
    var clip: TimelineClip
    var preferredTransform: CGAffineTransform
    var still: CIImage?
    var title: TitleContent? = nil
    var incoming: TransitionWindow? = nil
    var outgoing: TransitionWindow? = nil
}
struct RenderGroup {
    var clip: TimelineClip
    var children: [RenderNode]
    var settings: ProjectSettings? = nil
    var incoming: TransitionWindow? = nil
    var outgoing: TransitionWindow? = nil
}
indirect enum RenderNode {
    case layer(RenderLayer)
    case group(RenderGroup)
    var clip: TimelineClip { switch self { case .layer(let layer): return layer.clip; case .group(let group): return group.clip } }
    var incoming: TransitionWindow? { switch self { case .layer(let layer): return layer.incoming; case .group(let group): return group.incoming } }
    var outgoing: TransitionWindow? { switch self { case .layer(let layer): return layer.outgoing; case .group(let group): return group.outgoing } }
    var start: Int64 { incoming?.start ?? clip.start }
    var end: Int64 { outgoing?.end ?? clip.end }
    var sourceTracks: [CMPersistentTrackID] {
        switch self {
        case .layer(let layer): return layer.still == nil && layer.title == nil ? [layer.trackID] : []
        case .group(let group): return group.children.flatMap(\.sourceTracks)
        }
    }
}
extension RenderLayer {
    var start: Int64 { incoming?.start ?? clip.start }
    var end: Int64 { outgoing?.end ?? clip.end }
}
final class RenderInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    var timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid
    var requiredSourceTrackIDs: [NSValue]?
    let nodes: [RenderNode]
    let frameRate: FrameRate
    let designSize: CGSize
    init(range: CMTimeRange,nodes: [RenderNode],clock: CMPersistentTrackID,frameRate: FrameRate,designSize: CGSize) {
        timeRange = range; self.nodes = nodes; self.frameRate = frameRate; self.designSize = designSize
        requiredSourceTrackIDs = Set([clock] + nodes.flatMap(\.sourceTracks)).sorted().map { NSNumber(value: $0) }
    }
    convenience init(range: CMTimeRange,layers: [RenderLayer],clock: CMPersistentTrackID,frameRate: FrameRate,designSize: CGSize) {
        self.init(range: range,nodes: layers.map(RenderNode.layer),clock: clock,frameRate: frameRate,designSize: designSize)
    }
}
