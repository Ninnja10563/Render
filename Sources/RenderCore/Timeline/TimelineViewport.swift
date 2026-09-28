import Foundation

public enum TimelineViewport {
    /// Fixed-height track rows share one vertical range across headers and clip lanes.
    public static func rows(count: Int,rowHeight: Double,headerHeight: Double,offset: Double,height: Double,overscan: Int = 2) -> Range<Int> {
        guard count > 0, rowHeight.isFinite, rowHeight > 0, headerHeight.isFinite, offset.isFinite, height.isFinite, height > 0 else { return 0..<0 }
        let padding = min(count,max(0,overscan))
        let top = min(Double(count),max(0,((offset - headerHeight) / rowHeight).rounded(.down)))
        let bottom = min(Double(count),max(0,((offset + height - headerHeight) / rowHeight).rounded(.up)))
        let first = max(0,Int(top) - padding), last = min(count,Int(bottom) + min(padding,count - Int(bottom)))
        return first..<max(first,last)
    }
}
