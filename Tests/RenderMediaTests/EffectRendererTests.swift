import XCTest
import CoreImage
import RenderCore
@testable import RenderMedia

final class EffectRendererTests: XCTestCase {
    let bounds = CGRect(x: 0,y: 0,width: 100,height: 100)
    private func rgba(_ image: CIImage,x: Int,y: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0,count: 4)
        bytes.withUnsafeMutableBytes { data in
            CIContext().render(image,toBitmap: data.baseAddress!,rowBytes: 4,bounds: CGRect(x: x,y: y,width: 1,height: 1),format: .RGBA8,colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        }
        return bytes
    }
    func testChromaCubeOutputsTransparentGreenAndOpaqueRed() {
        let renderer = EffectRenderer(), effect = Effect(kind: .chromaKey)
        let green = CIImage(color: CIColor(red: 0,green: 1,blue: 0)).cropped(to: bounds)
        let keyed = renderer.apply(effect,to: green,at: 0,sourceBounds: bounds,transform: .identity)
        XCTAssertLessThan(rgba(keyed,x: 50,y: 50)[3],5)
        let red = CIImage(color: CIColor(red: 1,green: 0,blue: 0)).cropped(to: bounds)
        let foreground = rgba(renderer.apply(effect,to: red,at: 0,sourceBounds: bounds,transform: .identity),x: 50,y: 50)
        XCTAssertGreaterThan(foreground[0],245); XCTAssertEqual(foreground[3],255)
    }
    func testMaskLimitsEffectAndFollowsClipTransform() {
        let renderer = EffectRenderer()
        let source = CIImage(color: CIColor(red: 1,green: 0,blue: 0)).cropped(to: bounds)
        var effect = Effect(kind: .opacity); effect.amount = 0
        var mask = EffectMask(); mask.shape = .rectangle; mask.feather = 0; mask.width = 0.4; mask.height = 0.4; effect.mask = mask
        let rendered = renderer.apply(effect,to: source,at: 0,sourceBounds: bounds,transform: .identity)
        XCTAssertLessThan(rgba(rendered,x: 50,y: 50)[3],5)
        XCTAssertGreaterThan(rgba(rendered,x: 10,y: 10)[3],245)
        mask.inverted = true; effect.mask = mask
        let inverted = renderer.apply(effect,to: source,at: 0,sourceBounds: bounds,transform: .identity)
        XCTAssertGreaterThan(rgba(inverted,x: 50,y: 50)[3],245)
        XCTAssertLessThan(rgba(inverted,x: 10,y: 10)[3],5)
        mask.inverted = false; effect.mask = mask
        let transform = CGAffineTransform(translationX: 100,y: 50)
        let shifted = renderer.apply(effect,to: source.transformed(by: transform),at: 0,sourceBounds: bounds,transform: transform)
        XCTAssertLessThan(rgba(shifted,x: 150,y: 100)[3],5)
        XCTAssertGreaterThan(rgba(shifted,x: 110,y: 60)[3],245)
    }
    func testAllColorEffectsProduceFiniteFrames() {
        let renderer = EffectRenderer(), source = CIImage(color: CIColor(red: 0.3,green: 0.4,blue: 0.5)).cropped(to: bounds)
        for kind in EffectKind.allCases {
            let output = renderer.apply(Effect(kind: kind),to: source,at: 0,sourceBounds: bounds,transform: .identity)
            XCTAssertEqual(output.extent,bounds,"\(kind)")
            XCTAssertEqual(rgba(output,x: 50,y: 50).count,4)
        }
    }
}
