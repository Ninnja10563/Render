import Foundation

/// Clipboard lanes preserve synchronization when selections span video and audio tracks.
public struct ClipboardLane: Sendable {
    public let trackID: UUID
    public let clips: [TimelineClip]
    public init(trackID: UUID, clips: [TimelineClip]) { self.trackID = trackID; self.clips = clips }
}
