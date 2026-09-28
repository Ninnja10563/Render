import AVFoundation
import CoreImage
import Metal
import RenderCore

/// Serial GPU submission; one CIContext is reused for the lifetime of a compositor.
public final class VideoCompositor: NSObject, AVVideoCompositing {
    public let sourcePixelBufferAttributes: [String: any Sendable]? = [kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]]
    public let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferMetalCompatibilityKey as String: true]
    private let scene = SceneRenderer()
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
                let frame = request.compositionTime.seconds * instruction.frameRate.value
                var canvas: CIImage
                do {
                    canvas = try scene.render(instruction.nodes,frame: frame,rate: instruction.frameRate,size: instruction.designSize) { track in
                        request.sourceFrame(byTrackID: track).map { CIImage(cvPixelBuffer: $0) }
                    }
                } catch { request.finish(with: error); return }
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
