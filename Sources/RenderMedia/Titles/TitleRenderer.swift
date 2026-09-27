import Foundation
import CoreText
import CoreImage
import RenderCore

/// Core Text drawing is isolated from AppKit UI; only active titles are rasterized and cached.
final class TitleRenderer {
    private struct Key: Hashable { let title: TitleContent; let width: Int; let height: Int }
    private var cache: [Key: CIImage] = [:]
    private var cacheBytes = 0
    func image(_ title: TitleContent,size: CGSize) throws -> CIImage {
        let key = Key(title: title,width: Int(size.width),height: Int(size.height))
        if let image = cache[key] { return image }
        let canvas = CGRect(origin: .zero,size: size)
        if title.text.isEmpty { return CIImage(color: .clear).cropped(to: canvas) }
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontFamilyNameAttribute: title.fontFamily,
            kCTFontTraitsAttribute: [kCTFontWeightTrait: title.weight]
        ] as CFDictionary)
        let font = CTFontCreateWithFontDescriptor(descriptor,title.fontSize,nil)
        var alignment: CTTextAlignment
        switch title.alignment { case .left: alignment = .left; case .center: alignment = .center; case .right: alignment = .right }
        let paragraph: CTParagraphStyle = withUnsafePointer(to: &alignment) { pointer in
            var setting = CTParagraphStyleSetting(spec: .alignment,valueSize: MemoryLayout<CTTextAlignment>.size,value: pointer)
            return CTParagraphStyleCreate(&setting,1)
        }
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color(title.color),
            NSAttributedString.Key(kCTStrokeColorAttributeName as String): color(title.outline),
            NSAttributedString.Key(kCTStrokeWidthAttributeName as String): -title.outlineWidth / title.fontSize * 100,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph
        ]
        let text = NSAttributedString(string: title.text,attributes: attributes)
        let setter = CTFramesetterCreateWithAttributedString(text)
        let maxWidth = size.width * 0.9
        let measured = CTFramesetterSuggestFrameSizeWithConstraints(setter,CFRange(location: 0,length: 0),nil,CGSize(width: maxWidth,height: size.height),nil)
        let width = min(maxWidth,max(1,ceil(measured.width) + 2))
        let height = min(size.height,max(1,ceil(measured.height) + title.fontSize * 0.2))
        let x: CGFloat
        switch title.alignment { case .left: x = size.width * 0.05; case .center: x = (size.width - width) / 2; case .right: x = size.width * 0.95 - width }
        let textRect = CGRect(x: x,y: (size.height - height) / 2,width: width,height: height)
        let background = textRect.insetBy(dx: -title.padding,dy: -title.padding)
        let margin = title.shadowBlur * 3 + max(abs(title.shadowX),abs(title.shadowY)) + title.outlineWidth + 2
        let bitmapRect = background.insetBy(dx: -margin,dy: -margin).intersection(canvas).integral
        let bitmapWidth = max(1,Int(bitmapRect.width)), bitmapHeight = max(1,Int(bitmapRect.height))
        let bytes = bitmapWidth * bitmapHeight * 4
        guard bytes <= 128 * 1024 * 1024,
              let context = CGContext(data: nil,width: bitmapWidth,height: bitmapHeight,bitsPerComponent: 8,bytesPerRow: bitmapWidth * 4,space: CGColorSpace(name: CGColorSpace.sRGB)!,bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw RenderError.invalid("Title is too large to render. Reduce the text or sequence size.") }
        context.translateBy(x: -bitmapRect.minX,y: -bitmapRect.minY)
        context.setFillColor(color(title.background)); context.fill(background)
        context.setShadow(offset: CGSize(width: title.shadowX,height: title.shadowY),blur: title.shadowBlur,color: color(title.shadow))
        context.textMatrix = .identity
        let frame = CTFramesetterCreateFrame(setter,CFRange(location: 0,length: 0),CGPath(rect: textRect,transform: nil),nil)
        CTFrameDraw(frame,context)
        guard let bitmap = context.makeImage() else { throw RenderError.invalid("Unable to draw title.") }
        let image = CIImage(cgImage: bitmap).transformed(by: CGAffineTransform(translationX: bitmapRect.minX,y: bitmapRect.minY))
            .composited(over: CIImage(color: .clear).cropped(to: canvas)).cropped(to: canvas)
        if cacheBytes + bytes > 64 * 1024 * 1024 { cache.removeAll(keepingCapacity: true); cacheBytes = 0 }
        if bytes <= 64 * 1024 * 1024 { cache[key] = image; cacheBytes += bytes }
        return image
    }
    private func color(_ value: RGBAColor) -> CGColor {
        CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,components: [value.red,value.green,value.blue,value.alpha])!
    }
}
