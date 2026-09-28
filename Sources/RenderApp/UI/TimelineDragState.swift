import SwiftUI
import RenderCore

@MainActor
final class TimelineDragState: ObservableObject {
    @Published private(set) var active = false
    @Published private(set) var positions: [TrackMovePlan.Placement] = []
    @Published private(set) var issue: String?
    @Published private(set) var delta: Int64 = 0
    @Published private(set) var trackOffset = 0
    private var plan: TrackMovePlan?
    private var ids: Set<UUID> = []
    private var cancelled = false
    func begin(project: RenderProject,selection: Set<UUID>) throws {
        let snapshot = try TrackMovePlan(project: project,clips: selection)
        let initial = try snapshot.placements(delta: 0,trackOffset: 0)
        plan = snapshot; ids = selection
        cancelled = false; active = true; issue = nil; delta = 0; trackOffset = 0
        positions = initial
    }
    func update(delta proposed: Int64,trackOffset offset: Int) {
        guard active,!cancelled,let plan else { return }
        let next = max(-plan.earliest,proposed)
        guard next != delta || offset != trackOffset else { return }
        delta = next; trackOffset = offset
        do { positions = try plan.placements(delta: next,trackOffset: offset); issue = nil }
        catch { issue = error.localizedDescription }
    }
    func cancel() { cancelled = true; active = false; positions = []; issue = nil }
    func finish() throws -> TimelineCommand? {
        defer { active = false; positions = []; issue = nil; plan = nil }
        guard !cancelled, active,delta != 0 || trackOffset != 0 else { return nil }
        if let issue { throw RenderError.invalid(issue) }
        return trackOffset == 0 ? .move(clips: ids,delta: delta) : .moveAcrossTracks(clips: ids,delta: delta,trackOffset: trackOffset)
    }
}

struct TimelineDragOverlay: View {
    @ObservedObject var drag: TimelineDragState
    let frameRate: FrameRate
    let pointsPerSecond: Double
    let laneHeight: CGFloat
    let visibleRows: Range<Int>
    let visibleRange: ClosedRange<CGFloat>
    var body: some View {
        ZStack(alignment: .topLeading) {
            if drag.active {
                ForEach(drag.positions.filter { visibleRows.contains($0.targetTrack) && frameRate.seconds($0.start + $0.clip.duration) * pointsPerSecond >= visibleRange.lowerBound && frameRate.seconds($0.start) * pointsPerSecond <= visibleRange.upperBound }) { position in
                    let colour: Color = drag.issue == nil ? .accentColor : .red
                    Text(position.clip.name).font(.system(size: 10,weight: .medium)).lineLimit(1)
                        .padding(.horizontal,7).frame(width: max(3,frameRate.seconds(position.clip.duration) * pointsPerSecond),height: laneHeight - 10,alignment: .topLeading)
                        .background(colour.opacity(0.3)).overlay { Rectangle().strokeBorder(colour,lineWidth: 2) }
                        .offset(x: frameRate.seconds(position.start) * pointsPerSecond,y: 28 + CGFloat(position.targetTrack) * laneHeight + 5)
                }
            }
        }.frame(maxWidth: .infinity,maxHeight: .infinity,alignment: .topLeading).allowsHitTesting(false)
    }
}

struct TimelineDragHint: View {
    @ObservedObject var drag: TimelineDragState
    var body: some View {
        if drag.active {
            Text(drag.issue ?? "Move \(drag.delta > 0 ? "+" : "")\(drag.delta)f · \(drag.trackOffset > 0 ? "+" : "")\(drag.trackOffset) tracks · Esc to cancel")
                .font(.system(size: 10)).foregroundStyle(drag.issue == nil ? Color.secondary : .red).lineLimit(1)
        }
    }
}
