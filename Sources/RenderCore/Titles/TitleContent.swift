import Foundation

public struct RGBAColor: Codable, Equatable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double
    public init(_ red: Double,_ green: Double,_ blue: Double,_ alpha: Double = 1) { self.red = red; self.green = green; self.blue = blue; self.alpha = alpha }
    public var isValid: Bool { [red,green,blue,alpha].allSatisfy { $0.isFinite && (0...1).contains($0) } }
}
public enum TitleRole: String, Codable, Sendable { case title, caption }
public enum TextAlignment: String, Codable, CaseIterable, Sendable { case left, center, right }
public struct TitleContent: Codable, Equatable, Hashable, Sendable {
    public var text: String = "Title"
    public var role: TitleRole = .title
    public var fontFamily: String = "Helvetica Neue"
    public var weight: Double = 0
    public var fontSize: Double = 72
    public var alignment: TextAlignment = .center
    public var color = RGBAColor(1,1,1)
    public var outline = RGBAColor(0,0,0)
    public var outlineWidth: Double = 0
    public var shadow = RGBAColor(0,0,0,0.65)
    public var shadowBlur: Double = 4
    public var shadowX: Double = 0
    public var shadowY: Double = -2
    public var background = RGBAColor(0,0,0,0)
    public var padding: Double = 16
    public init(text: String = "Title",role: TitleRole = .title) { self.text = text; self.role = role }
    public func validate() throws {
        guard text.utf8.count <= 40_000, fontFamily.utf8.count <= 256,
              [weight,fontSize,outlineWidth,shadowBlur,shadowX,shadowY,padding].allSatisfy(\.isFinite),
              (-1...1).contains(weight), (8...500).contains(fontSize), (0...30).contains(outlineWidth),
              (0...100).contains(shadowBlur), abs(shadowX) <= 500, abs(shadowY) <= 500, (0...200).contains(padding),
              [color,outline,shadow,background].allSatisfy(\.isValid) else { throw RenderError.invalid("Invalid title text or styling.") }
    }
}
