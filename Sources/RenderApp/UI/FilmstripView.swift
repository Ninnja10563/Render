import SwiftUI
import RenderCore
import RenderMedia

private struct FilmstripRequest: Hashable {
    let asset: UUID
    let url: URL
    let sourceIn: Double
    let speed: Double
    let pointsPerSecond: Double
    let first: Int
    let last: Int
    let mode: PlaybackMediaMode
}
struct FilmstripView: View {
    let media: MediaAsset
    let clip: TimelineClip
    let library: MediaLibrary
    let poster: NSImage?
    let pointsPerSecond: Double
    let frameRate: FrameRate
    let visibleRange: ClosedRange<CGFloat>
    let width: CGFloat
    let mode: PlaybackMediaMode
    @State private var images: [Int: CGImage] = [:]
    @State private var loaded: FilmstripRequest?
    private let cellWidth: CGFloat = 72
    private var request: FilmstripRequest {
        let origin = frameRate.seconds(clip.start) * pointsPerSecond
        let start = max(0,visibleRange.lowerBound - origin)
        let end = max(start,min(width,visibleRange.upperBound - origin))
        let first = max(0,Int((start / cellWidth).rounded(.down)))
        let last = min(first + 128,max(first,Int((end / cellWidth).rounded(.up))))
        return FilmstripRequest(asset: media.id,url: media.url,sourceIn: clip.sourceIn,speed: clip.speed,pointsPerSecond: pointsPerSecond,first: first,last: last,mode: mode)
    }
    var body: some View {
        let request = request
        ZStack(alignment: .leading) {
            ForEach(Array(request.first..<request.last),id: \.self) { index in
                Group {
                    if loaded == request, let image = images[index] { Image(decorative: image,scale: 2).resizable().scaledToFill() }
                    else if let poster { Image(nsImage: poster).resizable().scaledToFill() }
                    else { Color.black.opacity(0.12) }
                }.frame(width: cellWidth,height: 37).clipped().offset(x: CGFloat(index) * cellWidth)
            }
        }.frame(width: width,height: 37,alignment: .leading).clipped().allowsHitTesting(false)
            .task(id: request) {
                if media.kind == .image { images = [:]; loaded = request; return }
                do {
                    let indices = Array(request.first..<request.last)
                    let times = indices.map { clip.sourceIn + Double($0) * Double(cellWidth) / pointsPerSecond * clip.speed }
                    let frames = try await library.filmstrip(media,seconds: times,mode: mode)
                    try Task.checkCancellation()
                    images = Dictionary(uniqueKeysWithValues: zip(indices,frames)); loaded = request
                } catch { if !Task.isCancelled { images = [:]; loaded = request } }
            }
    }
}
