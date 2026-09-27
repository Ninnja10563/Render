import CoreImage
import RenderCore

/// Shared by preview and export. The owning compositor serializes calls and owns bounded caches.
final class EffectRenderer {
    private struct CubeKey: Hashable { var settings: ChromaKeySettings; var tolerance: Double }
    private struct MaskKey: Hashable { var mask: EffectMask; var width: Int; var height: Int }
    private var cubes: [CubeKey: Data] = [:]
    private var masks: [MaskKey: CIImage] = [:]

    func apply(_ effect: Effect,to input: CIImage,at frame: Double,sourceBounds: CGRect,transform: CGAffineTransform) -> CIImage {
        let value = effect.animation.value(at: frame,fallback: effect.amount)
        let filtered: CIImage
        switch effect.kind {
        case .exposure: filtered = input.applyingFilter("CIExposureAdjust",parameters: [kCIInputEVKey: value])
        case .brightness: filtered = input.applyingFilter("CIColorControls",parameters: [kCIInputBrightnessKey: value])
        case .contrast: filtered = input.applyingFilter("CIColorControls",parameters: [kCIInputContrastKey: value])
        case .saturation: filtered = input.applyingFilter("CIColorControls",parameters: [kCIInputSaturationKey: value])
        case .gaussianBlur: filtered = input.clampedToExtent().applyingFilter("CIGaussianBlur",parameters: [kCIInputRadiusKey: value]).cropped(to: input.extent)
        case .sharpen: filtered = input.applyingFilter("CISharpenLuminance",parameters: [kCIInputSharpnessKey: value])
        case .vignette: filtered = input.applyingFilter("CIVignette",parameters: [kCIInputIntensityKey: value])
        case .highlights: filtered = input.applyingFilter("CIHighlightShadowAdjust",parameters: ["inputHighlightAmount": value,"inputShadowAmount": 0])
        case .shadows: filtered = input.applyingFilter("CIHighlightShadowAdjust",parameters: ["inputHighlightAmount": 1,"inputShadowAmount": value])
        case .temperature: filtered = input.applyingFilter("CITemperatureAndTint",parameters: ["inputNeutral": CIVector(x: 6500,y: 0),"inputTargetNeutral": CIVector(x: value,y: 0)])
        case .tint: filtered = input.applyingFilter("CITemperatureAndTint",parameters: ["inputNeutral": CIVector(x: 6500,y: 0),"inputTargetNeutral": CIVector(x: 6500,y: value)])
        case .opacity: filtered = input.applyingFilter("CIColorMatrix",parameters: ["inputAVector": CIVector(x: 0,y: 0,z: 0,w: value)])
        case .chromaKey:
            let key = CubeKey(settings: effect.keying ?? ChromaKeySettings(),tolerance: value)
            let data: Data
            if let cached = cubes[key] { data = cached }
            else {
                // Apple's CIColorCube recipe requires premultiplied RGBA, with red varying fastest.
                // https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/CoreImaging/ci_filer_recipes/ci_filter_recipes.html
                var values = [Float](); values.reserveCapacity(32 * 32 * 32 * 4)
                for b in 0..<32 { for g in 0..<32 { for r in 0..<32 {
                    let p = key.settings.sample(red: Double(r) / 31,green: Double(g) / 31,blue: Double(b) / 31,tolerance: value)
                    values.append(contentsOf: [Float(p.0),Float(p.1),Float(p.2),Float(p.3)])
                } } }
                data = values.withUnsafeBytes { Data($0) }
                if cubes.count >= 16 { cubes.removeAll(keepingCapacity: true) }
                cubes[key] = data
            }
            filtered = input.applyingFilter("CIColorCubeWithColorSpace",parameters: ["inputCubeDimension": 32,"inputCubeData": data,"inputColorSpace": CGColorSpace(name: CGColorSpace.sRGB)!])
        }
        guard let mask = effect.mask, let image = maskImage(mask,bounds: sourceBounds) else { return filtered }
        let positioned = image.transformed(by: transform).composited(over: CIImage(color: .black))
        return filtered.applyingFilter("CIBlendWithMask",parameters: [kCIInputBackgroundImageKey: input,kCIInputMaskImageKey: positioned]).cropped(to: input.extent)
    }

    private func maskImage(_ mask: EffectMask,bounds: CGRect) -> CIImage? {
        let key = MaskKey(mask: mask,width: Int(bounds.width),height: Int(bounds.height))
        if let cached = masks[key] { return cached }
        let factor = min(1,1024 / max(bounds.width,bounds.height))
        let width = max(1,Int(bounds.width * factor)), height = max(1,Int(bounds.height * factor))
        guard let context = CGContext(data: nil,width: width,height: height,bitsPerComponent: 8,bytesPerRow: width,space: CGColorSpaceCreateDeviceGray(),bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.setFillColor(gray: 0,alpha: 1); context.fill(CGRect(x: 0,y: 0,width: width,height: height))
        context.setFillColor(gray: 1,alpha: 1)
        let rect = CGRect(x: (mask.x - mask.width / 2) * Double(width),y: (mask.y - mask.height / 2) * Double(height),width: mask.width * Double(width),height: mask.height * Double(height))
        switch mask.shape {
        case .rectangle: context.fill(rect)
        case .ellipse: context.fillEllipse(in: rect)
        case .polygon:
            for (index,point) in mask.points.enumerated() {
                let position = CGPoint(x: rect.minX + point.x * rect.width,y: rect.minY + point.y * rect.height)
                if index == 0 { context.move(to: position) } else { context.addLine(to: position) }
            }
            context.closePath(); context.fillPath()
        }
        guard let bitmap = context.makeImage() else { return nil }
        var image = CIImage(cgImage: bitmap).transformed(by: CGAffineTransform(scaleX: bounds.width / Double(width),y: bounds.height / Double(height)))
        let shortSide = min(bounds.width,bounds.height)
        if mask.expansion != 0 {
            image = image.clampedToExtent().applyingFilter(mask.expansion > 0 ? "CIMorphologyMaximum" : "CIMorphologyMinimum",parameters: [kCIInputRadiusKey: abs(mask.expansion) * shortSide]).cropped(to: bounds)
        }
        if mask.feather > 0 { image = image.clampedToExtent().applyingFilter("CIGaussianBlur",parameters: [kCIInputRadiusKey: mask.feather * shortSide]).cropped(to: bounds) }
        if mask.inverted { image = image.applyingFilter("CIColorInvert") }
        if masks.count >= 16 { masks.removeAll(keepingCapacity: true) }
        masks[key] = image
        return image
    }
}
