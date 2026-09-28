import Foundation
import RenderCore

extension EditorSession {
    func openSource(_ id: UUID) {
        guard let media = project.assets.first(where: { $0.id == id }),flushInspectorEdits() else { return }
        pause(); selection = []; selectedRange = nil; timelineDrag.cancel(); selectedAsset = id; showingSource = true; sourceMonitor.configure(media,rate: fps)
    }
    func closeSource() { sourceMonitor.pause(); showingSource = false }
    func markSource(incoming: Bool) {
        guard showingSource,let asset = sourceMonitor.asset else { return }
        var range = sourceMonitor.range
        let sourceRate = sourceMonitor.rate
        if incoming {
            range.start = sourceRate.seconds(sourceMonitor.frame)
            range.end = max(range.end,min(asset.duration,sourceRate.seconds(sourceMonitor.frame + 1)))
        } else {
            range.end = min(asset.duration,sourceRate.seconds(sourceMonitor.frame + 1))
            range.start = min(range.start,sourceRate.seconds(sourceMonitor.frame))
        }
        perform(.sourceSelection(asset: asset.id,range))
    }
    func clearSourceMarks() { if showingSource,let asset = sourceMonitor.asset { perform(.sourceSelection(asset: asset.id,nil)) } }
    func editSource(insert: Bool = false,overwrite: Bool = false) {
        guard showingSource,let id = sourceMonitor.asset?.id else { return }
        sourceMonitor.pause(); append(id,atPlayhead: insert || overwrite,insert: insert,overwrite: overwrite)
    }
}
