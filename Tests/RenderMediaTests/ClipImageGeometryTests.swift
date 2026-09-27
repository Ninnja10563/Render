import XCTest
import CoreImage
import RenderCore
@testable import RenderMedia

final class ClipImageGeometryTests: XCTestCase {
    let source = CGRect(x: 0,y: 0,width: 200,height: 100)
    let canvas = CGRect(x: 0,y: 0,width: 400,height: 200)
    func testAnchorChangeAlonePreservesPlacementAndScaleUsesPivot() throws {
        var p = ClipProperties(); try p.setBaseValue("anchorX",value: 0)
        let identity = ClipImageGeometry.transform(source: source,canvas: canvas,properties: p,frame: 0)
        XCTAssertEqual(CGPoint(x: 0,y: 0).applying(identity),CGPoint(x: 0,y: 0))
        XCTAssertEqual(CGPoint(x: 200,y: 100).applying(identity),CGPoint(x: 400,y: 200))
        try p.setBaseValue("scaleX",value: 2)
        let scaled = ClipImageGeometry.transform(source: source,canvas: canvas,properties: p,frame: 0)
        XCTAssertEqual(CGPoint(x: 0,y: 50).applying(scaled),CGPoint(x: 0,y: 100))
        XCTAssertEqual(CGPoint(x: 200,y: 50).applying(scaled),CGPoint(x: 800,y: 100))
    }
    func testFlipCropAndAnimatedCropBounds() throws {
        var p = ClipProperties(); p.geometry = ClipGeometry(); p.geometry?.flipHorizontal = true
        let flip = ClipImageGeometry.transform(source: source,canvas: canvas,properties: p,frame: 0)
        XCTAssertEqual(CGPoint(x: 0,y: 50).applying(flip),CGPoint(x: 400,y: 100))
        try p.setBaseValue("cropLeft",value: 0.25); try p.setBaseValue("cropTop",value: 0.5)
        XCTAssertEqual(ClipImageGeometry.crop(source: source,properties: p,frame: 0),CGRect(x: 50,y: 0,width: 150,height: 50))
        p.animations["cropRight"] = AnimationCurve(keys: [Keyframe(frame: 0,value: 0),Keyframe(frame: 30,value: 1)])
        XCTAssertTrue(ClipImageGeometry.crop(source: source,properties: p,frame: 30).isEmpty)
    }
    func testBlendModesRenderDistinctExpectedColors() {
        let bounds = CGRect(x: 0,y: 0,width: 8,height: 8)
        let red = CIImage(color: CIColor(red: 1,green: 0,blue: 0)).cropped(to: bounds)
        let blue = CIImage(color: CIColor(red: 0,green: 0,blue: 1)).cropped(to: bounds)
        func pixel(_ mode: BlendMode) -> [UInt8] {
            var values = [UInt8](repeating: 0,count: 4)
            values.withUnsafeMutableBytes { pointer in
                CIContext().render(ClipImageGeometry.blend(red,over: blue,mode: mode),toBitmap: pointer.baseAddress!,rowBytes: 4,bounds: CGRect(x: 1,y: 1,width: 1,height: 1),format: .RGBA8,colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            }
            return values
        }
        XCTAssertEqual(pixel(.normal),[255,0,0,255])
        XCTAssertEqual(pixel(.multiply),[0,0,0,255])
        XCTAssertEqual(pixel(.screen),[255,0,255,255])
        for mode in BlendMode.allCases { XCTAssertEqual(pixel(mode)[3],255) }
    }
}
