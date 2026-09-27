import AVFoundation
import CoreImage
import Metal
import RenderCore

struct RenderLayer {
    var trackID: CMPersistentTrackID
    var clip: TimelineClip
    var preferredTransform: CGAffineTransform
    var still: CIImage?
    var title: TitleContent? = nil
}
final class RenderInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    var timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid
    var requiredSourceTrackIDs: [NSValue]?
    let layers: [RenderLayer]
    let frameRate: FrameRate
    let designSize: CGSize
    init(range: CMTimeRange, layers: [RenderLayer], clock: CMPersistentTrackID, frameRate: FrameRate,designSize: CGSize) {
        timeRange = range; self.layers = layers; self.frameRate = frameRate; self.designSize = designSize
        requiredSourceTrackIDs = ([clock] + layers.filter { $0.still == nil && $0.title == nil }.map(\.trackID)).map { NSNumber(value: $0) }
    }
}

/// Serial GPU submission; one CIContext is reused for the lifetime of a compositor.
public final class VideoCompositor: NSObject, AVVideoCompositing {
    public let sourcePixelBufferAttributes: [String: any Sendable]? = [kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]]
    public let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferMetalCompatibilityKey as String: true]
    private let titles = TitleRenderer()
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
                let outputBounds = CGRect(origin: .zero,size: request.renderContext.size)
                let bounds = CGRect(origin: .zero,size: instruction.designSize)
                var canvas = CIImage(color: .black).cropped(to: bounds)
                for layer in instruction.layers.reversed() {
                    let source: CIImage
                    if let title = layer.title {
                        do { source = try titles.image(title,size: instruction.designSize) }
                        catch { request.finish(with: error); return }
                    }
                    else if let still = layer.still { source = still }
                    else if let pixel = request.sourceFrame(byTrackID: layer.trackID) { source = CIImage(cvPixelBuffer: pixel).transformed(by: layer.preferredTransform) }
                    else { request.finish(with: RenderError.invalid("A source video frame could not be decoded.")); return }
                    let frame = request.compositionTime.seconds * instruction.frameRate.value - Double(layer.clip.start) + Double(layer.clip.animationOffset)
                    let p = layer.clip.properties
                    var image = source.transformed(by: CGAffineTransform(translationX: -source.extent.minX, y: -source.extent.minY))
                    let sourceBounds = image.extent
                    let transform = ClipImageGeometry.transform(source: sourceBounds,canvas: bounds,properties: p,frame: frame)
                    let crop = ClipImageGeometry.crop(source: sourceBounds,properties: p,frame: frame)
                    if crop.isEmpty { continue }
                    image = image.cropped(to: crop).transformed(by: transform)
                    for effect in layer.clip.effects where effect.enabled {
                        do { image = try effects.apply(effect,to: image,at: frame,sourceBounds: sourceBounds,transform: transform) }
                        catch { request.finish(with: error); return }
                    }
                    image = image.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: p.value("opacity", at: frame))])
                    canvas = ClipImageGeometry.blend(image,over: canvas,mode: p.geometry?.blend ?? .normal).cropped(to: bounds)
                }
                let outputScale = min(outputBounds.width / bounds.width,outputBounds.height / bounds.height)
                canvas = canvas.transformed(by: CGAffineTransform(scaleX: outputScale,y: outputScale))
                    .transformed(by: CGAffineTransform(translationX: (outputBounds.width - bounds.width * outputScale) / 2,y: (outputBounds.height - bounds.height * outputScale) / 2))
                    .composited(over: CIImage(color: .black).cropped(to: outputBounds))
                context.render(canvas, to: buffer, bounds: outputBounds, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
                request.finish(withComposedVideoFrame: buffer)
            }
        }
    }
    public func cancelAllPendingVideoCompositionRequests() { queue.sync {} }
}
