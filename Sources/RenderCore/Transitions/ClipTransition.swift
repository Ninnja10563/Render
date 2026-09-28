import Foundation

public enum TransitionKind: String, Codable, CaseIterable, Sendable {
    case crossDissolve, fade, dipToBlack, dipToWhite, wipe, slide
    public var label: String {
        switch self {
        case .crossDissolve: return "Cross Dissolve"
        case .fade: return "Fade Through Transparent"
        case .dipToBlack: return "Dip to Black"
        case .dipToWhite: return "Dip to White"
        case .wipe: return "Wipe"
        case .slide: return "Slide"
        }
    }
}
public struct ClipTransition: Codable, Equatable, Sendable {
    public var rightID: UUID
    public var kind: TransitionKind
    public var duration: Int64
    public init(rightID: UUID,kind: TransitionKind,duration: Int64) { self.rightID = rightID; self.kind = kind; self.duration = duration }
}
public struct TransitionWindow: Sendable {
    public var leftID: UUID
    public var rightID: UUID
    public var kind: TransitionKind
    public var start: Int64
    public var end: Int64
    public var duration: Int64 { end - start }
    public init(left: TimelineClip,transition: ClipTransition) {
        leftID = left.id; rightID = transition.rightID; kind = transition.kind
        start = left.end - transition.duration / 2; end = start + transition.duration
    }
    public func progress(at frame: Double) -> Double { max(0,min(1,(frame - Double(start)) / Double(max(1,duration)))) }
}
public enum TransitionEditing {
    public static func validate(_ transition: ClipTransition,left: TimelineClip,right: TimelineClip?,project: RenderProject,assets: [UUID:MediaAsset]? = nil) throws {
        guard let right, right.id == transition.rightID, left.end == right.start,
              transition.duration >= 2, transition.duration <= min(left.duration,right.duration) else { throw RenderError.invalid("A transition needs adjacent clips and a duration no longer than either clip.") }
        let before = transition.duration / 2, after = transition.duration - before
        let media = assets ?? Dictionary(uniqueKeysWithValues: project.assets.map { ($0.id,$0) })
        func duration(_ clip: TimelineClip) -> Double? {
            if let id = clip.compoundID { return project.compounds?.first(where: { $0.id == id })?.seconds }
            if let id = clip.assetID, let source = media[id], source.kind != .image { return source.duration }
            return nil
        }
        if let duration = duration(left) {
            guard left.sourceIn + project.settings.frameRate.seconds(left.duration + after) * left.speed <= duration + 0.001 else {
                throw RenderError.invalid("The outgoing clip needs more source frames after the cut. Trim its end before adding this transition.")
            }
        }
        if duration(right) != nil {
            guard right.sourceIn + 0.001 >= project.settings.frameRate.seconds(before) * right.speed else {
                throw RenderError.invalid("The incoming clip needs more source frames before the cut. Trim its beginning before adding this transition.")
            }
        }

    }
    static func reconcile(_ project: inout RenderProject) {
        guard project.tracks.contains(where: { $0.clips.contains(where: { $0.transition != nil }) }) else { return }
        let assets = Dictionary(uniqueKeysWithValues: project.assets.map { ($0.id,$0) })
        // Structural edits that break a transition remove it in the same undoable transaction.
        for t in project.tracks.indices {
            let clips = Dictionary(uniqueKeysWithValues: project.tracks[t].clips.map { ($0.id,$0) })
            for c in project.tracks[t].clips.indices {
                let left = project.tracks[t].clips[c]
                if let transition = left.transition {
                    do { try validate(transition,left: left,right: clips[transition.rightID],project: project,assets: assets) }
                    catch { project.tracks[t].clips[c].transition = nil }
                }
            }
        }
    }
}
