import XCTest
import CoreImage
import RenderCore
@testable import RenderMedia

final class TransitionRendererTests: XCTestCase {
    func testEveryTransitionHasCorrectEndpointsAndMidpointCoverage() {
        let bounds = CGRect(x: 0,y: 0,width: 100,height: 100)
        let red = CIImage(color: CIColor(red: 1,green: 0,blue: 0)).cropped(to: bounds)
        let blue = CIImage(color: CIColor(red: 0,green: 0,blue: 1)).cropped(to: bounds)
        let background = CIImage(color: CIColor(red: 0,green: 1,blue: 0)).cropped(to: bounds)
        func pixel(_ kind: TransitionKind,_ time: Double,_ x: Int = 50) -> [UInt8] {
            let image = TransitionRenderer.composite(red,blue,over: background,outMode: .normal,inMode: .normal,kind: kind,progress: time,bounds: bounds)
            var bytes = [UInt8](repeating: 0,count: 4)
            bytes.withUnsafeMutableBytes { data in CIContext().render(image,toBitmap: data.baseAddress!,rowBytes: 4,bounds: CGRect(x: x,y: 50,width: 1,height: 1),format: .RGBA8,colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) }
            return bytes
        }
        for kind in TransitionKind.allCases {
            XCTAssertEqual(pixel(kind,0),[255,0,0,255],kind.rawValue)
            XCTAssertEqual(pixel(kind,1),[0,0,255,255],kind.rawValue)
        }
        let dissolve = pixel(.crossDissolve,0.5)
        XCTAssertGreaterThan(dissolve[0],100); XCTAssertGreaterThan(dissolve[2],100)
        XCTAssertEqual(pixel(.fade,0.5),[0,255,0,255])
        XCTAssertEqual(pixel(.dipToBlack,0.5),[0,0,0,255])
        XCTAssertEqual(pixel(.dipToWhite,0.5),[255,255,255,255])
        XCTAssertEqual(pixel(.wipe,0.5,10),[0,0,255,255]); XCTAssertEqual(pixel(.wipe,0.5,90),[255,0,0,255])
        XCTAssertEqual(pixel(.slide,0.5,10),[255,0,0,255]); XCTAssertEqual(pixel(.slide,0.5,90),[0,0,255,255])
    }
}
