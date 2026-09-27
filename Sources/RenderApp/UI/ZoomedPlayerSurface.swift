import SwiftUI
import AVKit

struct ZoomedPlayerSurface: View {
    let player: AVPlayer
    let sequenceSize: CGSize
    /// Zero fits the viewer; one maps each sequence pixel to one display pixel.
    let zoom: Double
    @State private var density: CGFloat = 2
    @State private var pan: CGSize = .zero
    @GestureState private var drag: CGSize = .zero
    var body: some View {
        GeometryReader { geometry in
            let fit = min(geometry.size.width / max(1,sequenceSize.width),geometry.size.height / max(1,sequenceSize.height))
            let scale = zoom == 0 ? 1 : zoom / max(0.001,fit * density)
            let limitX = max(0,(sequenceSize.width * fit * scale - geometry.size.width) / 2)
            let limitY = max(0,(sequenceSize.height * fit * scale - geometry.size.height) / 2)
            let x = min(limitX,max(-limitX,pan.width + drag.width))
            let y = min(limitY,max(-limitY,pan.height + drag.height))
            PlayerSurface(player: player).frame(width: geometry.size.width,height: geometry.size.height)
                .scaleEffect(scale).offset(x: x,y: y)
                .overlay {
                    Color.clear.contentShape(Rectangle())
                        .gesture(DragGesture().updating($drag) { value,state,_ in state = value.translation }.onEnded { value in
                            pan = CGSize(width: min(limitX,max(-limitX,pan.width + value.translation.width)),height: min(limitY,max(-limitY,pan.height + value.translation.height)))
                        })
                }
        }.clipped().onChange(of: zoom) { _,_ in pan = .zero }
            .onAppear { density = NSApp.keyWindow?.backingScaleFactor ?? 2 }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeBackingPropertiesNotification)) { _ in density = NSApp.keyWindow?.backingScaleFactor ?? 2 }
            .help(zoom == 0 ? "Fit to viewer" : "Drag to pan. 100% maps one sequence pixel to one display pixel.")
    }
}
