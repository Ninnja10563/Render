import SwiftUI
import AVKit
import RenderCore

struct WorkspaceView: View {
    @ObservedObject var session: EditorSession
    var body: some View {
        VStack(spacing: 0) {
            VSplitView {
                HSplitView {
                    if session.showLibrary { MediaBrowserView(session: session).frame(minWidth: 210, idealWidth: 270, maxWidth: 440) }
                    ViewerView(session: session).frame(minWidth: 380, maxWidth: .infinity, minHeight: 250, maxHeight: .infinity)
                    if session.showInspector { InspectorView(session: session).frame(minWidth: 250, idealWidth: 280, maxWidth: 380) }
                }.frame(minHeight: 280)
                if session.showTimeline { TimelineView(session: session).frame(minHeight: 200, idealHeight: 310) }
            }
            statusBar
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(session.project.name + (session.isDirty ? " •" : ""))
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { session.showLibrary.toggle() } label: { Image(systemName: "sidebar.left") }.help("Show or hide media browser")
                Button { session.importPanel() } label: { Label("Import", systemImage: "square.and.arrow.down") }.disabled(session.importing)
            }
            ToolbarItem(placement: .principal) {
                HStack(spacing: 10) {
                    Text("RENDER").font(.system(size: 11,weight: .bold,design: .rounded)).tracking(2)
                    Divider().frame(height: 14)
                    Text("\(session.project.settings.width) × \(session.project.settings.height)  ·  \(session.fps.value.formatted(.number.precision(.fractionLength(0...3)))) fps")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                BackgroundTasksButton(queue: session.backgroundTasks)
                Button { session.showInspector.toggle() } label: { Image(systemName: "sidebar.right") }.help("Show or hide inspector")
                Button { session.showExport = true } label: { Label("Export", systemImage: "square.and.arrow.up") }.disabled(session.project.duration == 0)
            }
        }
        .alert("Render couldn’t complete the operation", isPresented: Binding(get: { session.errorMessage != nil }, set: { if !$0 { session.errorMessage = nil } })) {
            Button("OK",role: .cancel) { session.errorMessage = nil }
        } message: { Text(session.errorMessage ?? "") }
        .sheet(isPresented: $session.showAudioSync) { AudioSyncView(session: session) }
        .sheet(isPresented: $session.showExport) { ExportView(session: session, exporter: session.exporter) }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            Task {
                var urls: [URL] = []
                for provider in providers {
                    let url: URL? = await withCheckedContinuation { continuation in
                        _ = provider.loadObject(ofClass: URL.self) { url,_ in continuation.resume(returning: url) }
                    }
                    if let url { urls.append(url) }
                }
                if urls.count == 1, let url = urls.first, url.pathExtension == "renderproject" { session.open(url) }
                else { session.importMedia(urls) }
            }
            return true
        }
    }
    private var statusBar: some View {
        HStack(spacing: 8) {
            if let activity = session.activity { ProgressView().controlSize(.mini); Text(activity) }
            else { Text(session.isDirty ? "Unsaved changes · Recovery enabled" : "\(session.project.assets.count) media items") }
            Spacer()
            Text(session.selection.isEmpty ? "\(session.project.tracks.flatMap(\.clips).count) clips" : "\(session.selection.count) selected")
            Text("·")
            Text("\(session.fps.timecode(session.project.duration)) NDF").monospacedDigit()
        }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal,12).frame(height: 25)
    }
}

struct PlayerSurface: NSViewRepresentable {
    let player: AVPlayer
    var gravity: AVLayerVideoGravity = .resizeAspect
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView(); view.player = player; view.controlsStyle = .none
        view.videoGravity = gravity; view.showsFullScreenToggleButton = false
        return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) { view.player = player; view.videoGravity = gravity }
}

private struct ViewerView: View {
    @ObservedObject var session: EditorSession
    @ObservedObject private var transport: TransportState
    @State private var zoom: Double = 0
    init(session: EditorSession) { self.session = session; transport = session.transport }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("VIEWER").font(.system(size: 10,weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Picker("Playback media",selection: $session.playbackMode) {
                    ForEach(PlaybackMediaMode.allCases,id: \.self) { mode in Text(mode.label).tag(mode) }
                }.labelsHidden().frame(width: 100).controlSize(.mini).help("Final export always uses originals")
                Menu(zoom == 0 ? "Fit" : "\(Int(zoom * 100))%") {
                    Button("Fit") { zoom = 0 }
                    Button("100% · Actual Pixels") { zoom = 1 }
                    Button("200%") { zoom = 2 }
                    Button("400%") { zoom = 4 }
                }.menuStyle(.borderlessButton).frame(width: 70)
            }.padding(.horizontal,12).frame(height: 32)
            if let notice = session.playbackNotice {
                Text(notice).font(.system(size: 9)).foregroundStyle(.secondary).padding(.horizontal,8).padding(.bottom,4)
            }
            ZStack {
                Color.black
                if session.project.duration > 0 {
                    ZoomedPlayerSurface(player: session.player,sequenceSize: CGSize(width: session.project.settings.width,height: session.project.settings.height),zoom: zoom)
                    if let error = session.previewError {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle").font(.title2)
                            Text(error).multilineTextAlignment(.center).frame(maxWidth: 380)
                            Button("Retry Playback") { session.rebuild() }
                        }.foregroundStyle(.white).padding(24).background(.black.opacity(0.85))
                    } else if !session.previewReady { ProgressView("Preparing timeline…").tint(.white).foregroundStyle(.white) }
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "play.rectangle").font(.system(size: 32,weight: .ultraLight))
                        Text("Your story starts here").font(.system(size: 15,weight: .medium))
                        Text("Import media, then add a clip to the timeline.").font(.system(size: 12)).foregroundStyle(.gray)
                        Button("Import Media…") { session.importPanel() }.padding(.top,6)
                    }.foregroundStyle(.white.opacity(0.8))
                }
            }.clipped().frame(maxWidth: .infinity,maxHeight: .infinity)
            HStack(spacing: 16) {
                Text(session.fps.timecode(session.playhead)).font(.system(size: 12,weight: .medium,design: .monospaced)).frame(minWidth: 92,alignment: .leading)
                Spacer(minLength: 0)
                Button { session.pause(); session.seek(0) } label: { Image(systemName: "backward.end.fill") }.help("Beginning (Home)")
                Button { session.pause(); session.seek(session.playhead - 1) } label: { Image(systemName: "backward.frame.fill") }.help("Previous frame (←)")
                Button { session.togglePlayback() } label: { Image(systemName: session.isPlaying ? "pause.fill" : "play.fill").frame(width: 18) }.help("Play / Pause (Space)")
                Button { session.pause(); session.seek(session.playhead + 1) } label: { Image(systemName: "forward.frame.fill") }.help("Next frame (→)")
                Button { session.pause(); session.seek(session.project.duration - 1) } label: { Image(systemName: "forward.end.fill") }.help("End (End)")
                Spacer(minLength: 0)
                Text(session.fps.timecode(session.project.duration)).font(.system(size: 11,design: .monospaced)).foregroundStyle(.secondary)
            }.buttonStyle(.plain).padding(.horizontal,14).frame(height: 42)
        }
    }
}
