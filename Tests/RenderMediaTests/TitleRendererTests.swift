import XCTest
import CoreImage
import RenderCore
@testable import RenderMedia

final class TitleRendererTests: XCTestCase {
    func testTitleDrawsTextWithTransparentSurroundingsAndBoundedExtent() throws {
        var title = TitleContent(text: "Render 日本語"); title.fontSize = 36; title.shadowBlur = 0; title.shadow.alpha = 0
        let image = try TitleRenderer().image(title,size: CGSize(width: 640,height: 360))
        XCTAssertEqual(image.extent,CGRect(x: 0,y: 0,width: 640,height: 360))
        var bytes = [UInt8](repeating: 0,count: 640 * 360 * 4)
        bytes.withUnsafeMutableBytes { pointer in
            CIContext().render(image,toBitmap: pointer.baseAddress!,rowBytes: 640 * 4,bounds: image.extent,format: .RGBA8,colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        }
        let alpha = stride(from: 3,to: bytes.count,by: 4).map { bytes[$0] }
        XCTAssertGreaterThan(alpha.filter { $0 > 100 }.count,100)
        XCTAssertLessThan(alpha.filter { $0 > 0 }.count,640 * 120)
        XCTAssertEqual(alpha[0],0); XCTAssertEqual(alpha.last,0)
    }
    func testEmptyTitleIsTransparent() throws {
        let image = try TitleRenderer().image(TitleContent(text: ""),size: CGSize(width: 320,height: 180))
        var bytes = [UInt8](repeating: 255,count: 4)
        bytes.withUnsafeMutableBytes { pointer in CIContext().render(image,toBitmap: pointer.baseAddress!,rowBytes: 4,bounds: CGRect(x: 100,y: 100,width: 1,height: 1),format: .RGBA8,colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) }
        XCTAssertEqual(bytes,[0,0,0,0])
    }
}
