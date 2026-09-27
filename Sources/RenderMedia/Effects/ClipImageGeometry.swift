import CoreImage
import RenderCore

/// Sequence-space geometry shared by playback and every export size.
enum ClipImageGeometry {
    static func transform(source: CGRect,canvas: CGRect,properties p: ClipProperties,frame: Double) -> CGAffineTransform {
        let fit = min(canvas.width / source.width,canvas.height / source.height)
        let anchor = CGPoint(x: source.width * p.value("anchorX",at: frame),y: source.height * p.value("anchorY",at: frame))
        let scale = fit * p.value("scale",at: frame)
        let x = scale * p.value("scaleX",at: frame) * (p.geometry?.flipHorizontal == true ? -1 : 1)
        let y = scale * p.value("scaleY",at: frame) * (p.geometry?.flipVertical == true ? -1 : 1)
        return CGAffineTransform(translationX: -anchor.x,y: -anchor.y)
            .concatenating(CGAffineTransform(scaleX: x,y: y))
            .concatenating(CGAffineTransform(rotationAngle: p.value("rotation",at: frame) * .pi / 180))
            .concatenating(CGAffineTransform(translationX: canvas.midX + p.value("x",at: frame) + (anchor.x - source.width / 2) * fit,
                                           y: canvas.midY + p.value("y",at: frame) + (anchor.y - source.height / 2) * fit))
    }
    static func crop(source: CGRect,properties p: ClipProperties,frame: Double) -> CGRect {
        let left = p.value("cropLeft",at: frame), right = p.value("cropRight",at: frame)
        let top = p.value("cropTop",at: frame), bottom = p.value("cropBottom",at: frame)
        return CGRect(x: source.minX + source.width * left,y: source.minY + source.height * bottom,
                      width: source.width * max(0,1 - left - right),height: source.height * max(0,1 - top - bottom))
    }
    static func blend(_ image: CIImage,over background: CIImage,mode: BlendMode) -> CIImage {
        let filter: String
        switch mode {
        case .normal: return image.composited(over: background)
        case .multiply: filter = "CIMultiplyBlendMode"
        case .screen: filter = "CIScreenBlendMode"
        case .overlay: filter = "CIOverlayBlendMode"
        case .add: filter = "CIAdditionCompositing"
        case .darken: filter = "CIDarkenBlendMode"
        case .lighten: filter = "CILightenBlendMode"
        }
        return image.applyingFilter(filter,parameters: [kCIInputBackgroundImageKey: background])
    }
}
