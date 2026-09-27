import CoreImage
import RenderCore

enum TransitionRenderer {
    static func composite(_ outgoing: CIImage,_ incoming: CIImage,over background: CIImage,outMode: BlendMode,inMode: BlendMode,kind: TransitionKind,progress: Double,bounds: CGRect) -> CIImage {
        let t = max(0,min(1,progress))
        func blend(_ image: CIImage,_ mode: BlendMode) -> CIImage { ClipImageGeometry.blend(image,over: background,mode: mode).cropped(to: bounds) }
        func dissolve(_ a: CIImage,_ b: CIImage,_ amount: Double) -> CIImage { a.applyingFilter("CIDissolveTransition",parameters: [kCIInputTargetImageKey: b,kCIInputTimeKey: amount]).cropped(to: bounds) }
        func opacity(_ image: CIImage,_ value: Double) -> CIImage { image.applyingFilter("CIColorMatrix",parameters: ["inputAVector": CIVector(x: 0,y: 0,z: 0,w: value)]) }
        switch kind {
        case .crossDissolve: return dissolve(blend(outgoing,outMode),blend(incoming,inMode),t)
        case .fade: return t < 0.5 ? blend(opacity(outgoing,1 - t * 2),outMode) : blend(opacity(incoming,t * 2 - 1),inMode)
        case .dipToBlack, .dipToWhite:
            let solid = CIImage(color: kind == .dipToBlack ? .black : .white).cropped(to: bounds)
            return t < 0.5 ? dissolve(blend(outgoing,outMode),solid,t * 2) : dissolve(solid,blend(incoming,inMode),t * 2 - 1)
        case .wipe:
            if t == 0 { return blend(outgoing,outMode) }; if t == 1 { return blend(incoming,inMode) }
            let left = CGRect(x: bounds.minX,y: bounds.minY,width: bounds.width * t,height: bounds.height)
            let right = CGRect(x: left.maxX,y: bounds.minY,width: bounds.width * (1 - t),height: bounds.height)
            return blend(incoming,inMode).cropped(to: left).composited(over: blend(outgoing,outMode).cropped(to: right)).cropped(to: bounds)
        case .slide:
            let out = outgoing.cropped(to: bounds).transformed(by: CGAffineTransform(translationX: -bounds.width * t,y: 0)).cropped(to: bounds)
            let next = incoming.cropped(to: bounds).transformed(by: CGAffineTransform(translationX: bounds.width * (1 - t),y: 0)).cropped(to: bounds)
            let base = ClipImageGeometry.blend(out,over: background,mode: outMode)
            return ClipImageGeometry.blend(next,over: base,mode: inMode).cropped(to: bounds)
        }
    }
}
