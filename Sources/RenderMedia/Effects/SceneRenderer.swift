import CoreImage
import CoreMedia
import RenderCore

/// Evaluates a hierarchical image graph on the compositor's serial queue.
/// Groups composite children over transparency before applying their own visual properties.
final class SceneRenderer {
    private let titles = TitleRenderer()
    private let effects = EffectRenderer()
    func render(_ nodes: [RenderNode],frame: Double,rate: FrameRate,size: CGSize,background: CIColor = .black,source: (CMPersistentTrackID) -> CIImage?) throws -> CIImage {
        try scene(nodes,frame: frame,rate: rate,bounds: CGRect(origin: .zero,size: size),background: background,depth: 0,source: source)
    }
    private func scene(_ nodes: [RenderNode],frame: Double,rate: FrameRate,bounds: CGRect,background: CIColor,depth: Int,source: (CMPersistentTrackID) -> CIImage?) throws -> CIImage {
        guard depth <= 16 else { throw RenderError.invalid("The render hierarchy is too deeply nested.") }
        let active = nodes.filter { frame >= Double($0.start) && frame < Double($0.end) }
        let paired = active.contains { $0.incoming != nil || $0.outgoing != nil }
        let byID = paired ? Dictionary(uniqueKeysWithValues: active.map { ($0.clip.id,$0) }) : [:]
        var canvas = CIImage(color: background).cropped(to: bounds)
        for node in active.reversed() {
            if let incoming = node.incoming, frame >= Double(incoming.start), frame < Double(incoming.end), byID[incoming.leftID] != nil { continue }
            let image = try nodeImage(node,frame: frame,rate: rate,bounds: bounds,depth: depth,source: source)
            if let transition = node.outgoing, frame >= Double(transition.start), frame < Double(transition.end), let right = byID[transition.rightID] {
                let next = try nodeImage(right,frame: frame,rate: rate,bounds: bounds,depth: depth,source: source)
                canvas = TransitionRenderer.composite(image,next,over: canvas,outMode: node.clip.properties.geometry?.blend ?? .normal,inMode: right.clip.properties.geometry?.blend ?? .normal,kind: transition.kind,progress: transition.progress(at: frame),bounds: bounds)
            } else {
                canvas = ClipImageGeometry.blend(image,over: canvas,mode: node.clip.properties.geometry?.blend ?? .normal).cropped(to: bounds)
            }
        }
        return canvas
    }
    private func nodeImage(_ node: RenderNode,frame: Double,rate: FrameRate,bounds: CGRect,depth: Int,source: (CMPersistentTrackID) -> CIImage?) throws -> CIImage {
        let image: CIImage
        switch node {
        case .layer(let layer):
            if let title = layer.title { image = try titles.image(title,size: bounds.size) }
            else if let still = layer.still { image = still }
            else if let decoded = source(layer.trackID) { image = decoded.transformed(by: layer.preferredTransform) }
            else { throw RenderError.invalid("A source video frame could not be decoded.") }
        case .group(let group):
            let localFrame = group.clip.sourceIn * rate.value + (frame - Double(group.clip.start)) * group.clip.speed
            image = try scene(group.children,frame: localFrame,rate: rate,bounds: bounds,background: .clear,depth: depth + 1,source: source)
        }
        let clip = node.clip, p = clip.properties
        let animationFrame = frame - Double(clip.start) + Double(clip.animationOffset)
        var result = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX,y: -image.extent.minY))
        let sourceBounds = result.extent
        let transform = ClipImageGeometry.transform(source: sourceBounds,canvas: bounds,properties: p,frame: animationFrame)
        let crop = ClipImageGeometry.crop(source: sourceBounds,properties: p,frame: animationFrame)
        if crop.isEmpty { return CIImage(color: .clear).cropped(to: bounds) }
        result = result.cropped(to: crop).transformed(by: transform)
        for effect in clip.effects where effect.enabled { result = try effects.apply(effect,to: result,at: animationFrame,sourceBounds: sourceBounds,transform: transform) }
        return result.applyingFilter("CIColorMatrix",parameters: ["inputAVector": CIVector(x: 0,y: 0,z: 0,w: p.value("opacity",at: animationFrame))])
    }
}
