import AVFoundation
import CoreImage
import Metal
import RenderCore

struct RenderLayer {
    var trackID: CMPersistentTrackID
    var clip: TimelineClip
    var preferredTransform: CGAffineTransform
    var still: CIImage?
}
final class RenderInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    var timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid
    var requiredSourceTrackIDs: [NSValue]?
    let layers: [RenderLayer]
    let frameRate: FrameRate
    init(range: CMTimeRange, layers: [RenderLayer], clock: CMPersistentTrackID, frameRate: FrameRate) {
        timeRange = range; self.layers = layers; self.frameRate = frameRate
        requiredSourceTrackIDs = ([clock] + layers.filter { $0.still == nil }.map(\.trackID)).map { NSNumber(value: $0) }
    }
}

/// Serial GPU submission; one CIContext is reused for the lifetime of a compositor.
public final class VideoCompositor: NSObject, AVVideoCompositing {
    public let sourcePixelBufferAttributes: [String: any Sendable]? = [kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]]
    public let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferMetalCompatibilityKey as String: true]
    private let effects = EffectRenderer()
    private let queue = DispatchQueue(label: "app.render.compositor", qos: .userInteractive)
    private let context: CIContext = {
        let options: [CIContextOption: Any] = [.cacheIntermediates: false, .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!]
        if let device = MTLCreateSystemDefaultDevice() { return CIContext(mtlDevice: device, options: options) }
        return CIContext(options: options)
    }()
    public func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}
    public func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        queue.async { [self] in
            autoreleasepool {
                guard let instruction = request.videoCompositionInstruction as? RenderInstruction,
                      let buffer = request.renderContext.newPixelBuffer() else {
                    request.finish(with: RenderError.invalid("Unable to allocate a video frame.")); return
                }
                let bounds = CGRect(origin: .zero, size: request.renderContext.size)
                var canvas = CIImage(color: .black).cropped(to: bounds)
                for layer in instruction.layers.reversed() {
                    let source: CIImage
                    if let still = layer.still { source = still }
                    else if let pixel = request.sourceFrame(byTrackID: layer.trackID) { source = CIImage(cvPixelBuffer: pixel).transformed(by: layer.preferredTransform) }
                    else { request.finish(with: RenderError.invalid("A source video frame could not be decoded.")); return }
                    let frame = request.compositionTime.seconds * instruction.frameRate.value - Double(layer.clip.start) + Double(layer.clip.animationOffset)
                    let p = layer.clip.properties
                    var image = source.transformed(by: CGAffineTransform(translationX: -source.extent.minX, y: -source.extent.minY))
                    let fit = min(bounds.width / image.extent.width, bounds.height / image.extent.height)
                    let scale = fit * p.value("scale", at: frame)
                    let sourceBounds = image.extent
                    let transform = CGAffineTransform(translationX: -image.extent.width / 2,y: -image.extent.height / 2)
                        .concatenating(CGAffineTransform(scaleX: scale,y: scale))
                        .concatenating(CGAffineTransform(rotationAngle: p.value("rotation",at: frame) * .pi / 180))
                        .concatenating(CGAffineTransform(translationX: bounds.midX + p.value("x",at: frame),y: bounds.midY + p.value("y",at: frame)))
                    image = image.transformed(by: transform)
                    for effect in layer.clip.effects where effect.enabled {
                        do { image = try effects.apply(effect,to: image,at: frame,sourceBounds: sourceBounds,transform: transform) }
                        catch { request.finish(with: error); return }
                    }
                    image = image.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: p.value("opacity", at: frame))])
                    canvas = image.composited(over: canvas).cropped(to: bounds)
                }
                context.render(canvas, to: buffer, bounds: bounds, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
                request.finish(withComposedVideoFrame: buffer)
            }
        }
    }
    public func cancelAllPendingVideoCompositionRequests() { queue.sync {} }
}
