import SwiftUI

/// High-frequency transport updates are isolated from the project and timeline clip views.
@MainActor
final class TransportState: ObservableObject {
    @Published var playhead: Int64 = 0
    @Published var isPlaying = false
    @Published var reversePreviewRate: Float = 0
}
