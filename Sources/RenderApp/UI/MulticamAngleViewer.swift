import SwiftUI
import AVKit
import RenderCore
import RenderMedia

struct MulticamAngleViewer: View {
    @ObservedObject var session: EditorSession
    @ObservedObject private var transport: TransportState
    @State private var page = 0
    init(session: EditorSession) { self.session = session; transport = session.transport }
    var body: some View {
        VStack(spacing: 5) {
            Divider()
            if let clip = session.selectedClip, let membership = clip.multicam,
               let source = session.project.multicamSources?.first(where: { $0.id == membership.sourceID }),
               let active = source.angles.first(where: { $0.id == membership.angleID }) {
                HStack {
                    Text("SOURCE ANGLES").font(.system(size: 9,weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    if source.angles.count > 4 {
                        Button { page = max(0,page - 1) } label: { Image(systemName: "chevron.left") }.disabled(page == 0)
                        Text("\(page + 1)").font(.caption)
                        Button { page = min((source.angles.count - 1) / 4,page + 1) } label: { Image(systemName: "chevron.right") }.disabled((page + 1) * 4 >= source.angles.count)
                    }
                }.buttonStyle(.plain).padding(.horizontal,10)
                HStack(spacing: 6) {
                    ForEach(Array(source.angles.dropFirst(page * 4).prefix(4))) { angle in
                        if let asset = session.project.assets.first(where: { $0.id == angle.assetID }) {
                            let seconds = clip.sourceIn - active.offset + angle.offset + session.fps.seconds(transport.playhead - clip.start) * clip.speed
                            CameraAngleTile(asset: asset,angle: angle,seconds: seconds,speed: clip.speed,playing: transport.isPlaying,mode: session.playbackMode,selected: angle.id == membership.angleID) {
                                session.switchCamera(angle.id,cut: true)
                            }
                        }
                    }
                }.padding(.horizontal,8).padding(.bottom,6)
                    .onChange(of: source.id) { _,_ in page = 0 }
            } else { Spacer(); Text("Select a multicam clip to view its cameras.").font(.caption).foregroundStyle(.secondary); Spacer() }
        }
    }
}

private struct CameraAngleTile: View {
    let asset: MediaAsset
    let angle: CameraAngle
    let seconds: Double
    let speed: Double
    let playing: Bool
    let mode: PlaybackMediaMode
    let selected: Bool
    let choose: () -> Void
    @State private var player = AVPlayer()
    private var available: Bool { seconds >= 0 && seconds < asset.duration }
    var body: some View {
        Button(action: choose) {
            VStack(spacing: 3) {
                ZStack {
                    PlayerSurface(player: player).allowsHitTesting(false)
                    if !available { Color.black; Text("Outside recording").font(.caption).foregroundStyle(.white) }
                }.frame(maxWidth: .infinity,maxHeight: .infinity).clipped()
                Text(angle.name).font(.system(size: 10)).lineLimit(1)
            }.padding(3).overlay(Rectangle().stroke(selected ? Color.accentColor : Color.secondary.opacity(0.3),lineWidth: selected ? 2 : 1))
        }.buttonStyle(.plain).disabled(!available)
            .onAppear { load() }
            .onChange(of: asset.id) { _,_ in load() }
            .onChange(of: mode) { _,_ in load() }
            .onChange(of: seconds) { _,_ in synchronize() }
            .onChange(of: playing) { _,_ in synchronize(force: true) }
            .onDisappear { player.pause(); player.replaceCurrentItem(with: nil) }
    }
    private func load() {
        player.isMuted = true
        player.replaceCurrentItem(with: AVPlayerItem(url: MediaResolver.url(for: asset,mode: mode)))
        synchronize(force: true)
    }
    private func synchronize(force: Bool = false) {
        guard available else { player.pause(); return }
        if force || !playing || abs(player.currentTime().seconds - seconds) > 0.2 {
            player.seek(to: CMTime(seconds: seconds,preferredTimescale: 60000),toleranceBefore: .zero,toleranceAfter: .zero)
        }
        if playing { player.rate = Float(speed) } else { player.pause() }
    }
}
