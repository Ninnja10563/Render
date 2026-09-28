import XCTest
import CoreImage
import AVFoundation
import RenderCore
@testable import RenderMedia

final class SceneRendererTests: XCTestCase {
    let size = CGSize(width: 100,height: 100)
    func layer(_ color: CIColor,start: Int64 = 0,duration: Int64 = 120) -> RenderNode {
        .layer(RenderLayer(trackID: kCMPersistentTrackID_Invalid,clip: TimelineClip(assetID: nil,name: "Test layer",start: start,duration: duration),preferredTransform: .identity,still: CIImage(color: color).cropped(to: CGRect(origin: .zero,size: size))))
    }
    func pixel(_ image: CIImage,x: Int = 50,y: Int = 50) -> [UInt8] {
        var rgba = [UInt8](repeating: 0,count: 4)
        rgba.withUnsafeMutableBytes { CIContext(options: [.workingColorSpace: NSNull(),.outputColorSpace: NSNull()]).render(image,toBitmap: $0.baseAddress!,rowBytes: 4,bounds: CGRect(x: x,y: y,width: 1,height: 1),format: .RGBA8,colorSpace: nil) }
        return rgba
    }
    func testParentOpacityAppliesAfterChildrenComposite() throws {
        var clip = TimelineClip(assetID: nil,name: "Group",start: 0,duration: 120)
        clip.properties.opacity = 0.5; clip.properties.scale = 0.5
        let group = RenderNode.group(RenderGroup(clip: clip,children: [layer(.red),layer(.green)]))
        let image = try SceneRenderer().render([group,layer(.blue)],frame: 0,rate: FrameRate(),size: size) { _ in nil }
        let center = pixel(image), edge = pixel(image,x: 5,y: 5)
        XCTAssertEqual(Double(center[0]),128,accuracy: 2); XCTAssertLessThan(center[1],2); XCTAssertEqual(Double(center[2]),128,accuracy: 2)
        XCTAssertLessThan(edge[0],2); XCTAssertGreaterThan(edge[2],250)
    }
    func testNestedTimingAndParentAnimationRemainIndependent() throws {
        let children = [layer(.red,duration: 30),layer(.green,start: 30,duration: 30)]
        let inner = RenderNode.group(RenderGroup(clip: TimelineClip(assetID: nil,name: "Inner",start: 0,duration: 60),children: children))
        var outer = TimelineClip(assetID: nil,name: "Outer",start: 30,duration: 30); outer.speed = 2
        outer.properties.animations["opacity"] = AnimationCurve(keys: [Keyframe(frame: 0,value: 0),Keyframe(frame: 30,value: 1)])
        let node = RenderNode.group(RenderGroup(clip: outer,children: [inner]))
        let renderer = SceneRenderer()
        let before = pixel(try renderer.render([node],frame: 44,rate: FrameRate(),size: size) { _ in nil })
        let after = pixel(try renderer.render([node],frame: 45,rate: FrameRate(),size: size) { _ in nil })
        XCTAssertGreaterThan(before[0],100); XCTAssertLessThan(before[1],2)
        XCTAssertLessThan(after[0],2); XCTAssertEqual(Double(after[1]),128,accuracy: 2)
    }
    func testGroupsParticipateInTransitionsAndEffects() throws {
        let a = TimelineClip(assetID: nil,name: "A",start: 0,duration: 30)
        var b = TimelineClip(assetID: nil,name: "B",start: 30,duration: 30); b.sourceIn = 1
        let window = TransitionWindow(left: a,transition: ClipTransition(rightID: b.id,kind: .crossDissolve,duration: 12))
        let nodes: [RenderNode] = [.group(RenderGroup(clip: a,children: [layer(.red)],outgoing: window)),.group(RenderGroup(clip: b,children: [layer(.blue)],incoming: window))]
        let renderer = SceneRenderer()
        let mixed = pixel(try renderer.render(nodes,frame: 30,rate: FrameRate(),size: size) { _ in nil })
        XCTAssertEqual(Double(mixed[0]),128,accuracy: 2); XCTAssertEqual(Double(mixed[2]),128,accuracy: 2)
        var effected = a; var saturation = Effect(kind: .saturation); saturation.amount = 0; effected.effects = [saturation]
        let gray = pixel(try renderer.render([.group(RenderGroup(clip: effected,children: [layer(.red)]))],frame: 10,rate: FrameRate(),size: size) { _ in nil })
        XCTAssertEqual(Double(gray[0]),Double(gray[1]),accuracy: 2); XCTAssertEqual(Double(gray[1]),Double(gray[2]),accuracy: 2)
    }
    func testFractionalRateRoundingDoesNotCreateBlackFramesAtCuts() throws {
        let nodes = [layer(.red,duration: 30),layer(.green,start: 30,duration: 30)]
        let value = pixel(try SceneRenderer().render(nodes,frame: Double(30).nextDown,rate: FrameRate(30000,1001),size: size) { _ in nil })
        XCTAssertGreaterThan(value[1],250); XCTAssertLessThan(value[0],2)
    }
    func testHierarchyLimitReportsError() {
        var node = layer(.red)
        for _ in 0..<18 { node = .group(RenderGroup(clip: TimelineClip(assetID: nil,name: "Nested",start: 0,duration: 120),children: [node])) }
        XCTAssertThrowsError(try SceneRenderer().render([node],frame: 0,rate: FrameRate(),size: size) { _ in nil })
    }
}
