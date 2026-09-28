import Foundation

public enum PreviewQuality: String, Codable, CaseIterable, Sendable {
    case full, half, quarter
    public var label: String { switch self { case .full: return "Full"; case .half: return "Half"; case .quarter: return "Quarter" } }
    public var divisor: Int { switch self { case .full: return 1; case .half: return 2; case .quarter: return 4 } }
    public func dimensions(for settings: ProjectSettings) -> (width: Int,height: Int) {
        (max(2,settings.width / divisor / 2 * 2),max(2,settings.height / divisor / 2 * 2))
    }
}
