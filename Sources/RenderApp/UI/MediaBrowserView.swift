import SwiftUI
import RenderCore

struct MediaBrowserView: View {
    @ObservedObject var session: EditorSession
    @State private var search = ""
    var filtered: [MediaAsset] { session.project.assets.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        VStack(spacing: 0) {
            PanelHeader("Media") {
                Text("\(session.project.assets.count)").monospacedDigit()
                Button { session.importPanel() } label: { Image(systemName: "plus") }
                    .help("Import media").accessibilityLabel("Import media")
            }
            TextField("Search media", text: $search).textFieldStyle(.roundedBorder).controlSize(.small).padding(10)
            if session.project.assets.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Text("No media imported").font(.system(size: 12,weight: .medium))
                    Text("Drop video, audio or images here.\nYour originals stay where they are.").font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Import Media…") { session.importPanel() }.padding(.top,4)
                    Spacer()
                }.frame(maxWidth: .infinity)
            } else if filtered.isEmpty {
                VStack(spacing: 8) {
                    Text("No matching media").font(.system(size: 12,weight: .medium))
                    Button("Clear Search") { search = "" }.controlSize(.small)
                }.frame(maxWidth: .infinity,maxHeight: .infinity)
            } else {
                List(selection: $session.selectedAsset) {
                    ForEach(filtered) { media in
                        HStack(spacing: 10) {
                            ZStack {
                                Color.black.opacity(0.2)
                                if let image = session.thumbnails[media.id] { Image(nsImage: image).resizable().scaledToFit() }
                                else { Image(systemName: media.kind == .audio ? "waveform" : "film").foregroundStyle(.secondary) }
                            }.frame(width: 64,height: 40).clipped()
                            VStack(alignment: .leading,spacing: 4) {
                                Text(media.name).font(.system(size: 11,weight: .medium)).lineLimit(1)
                                Text(media.kind == .audio ? "\(media.audioChannels) ch · \(media.codec)" : "\(media.width) × \(media.height) · \(media.codec)").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                Text(session.fps.timecode(session.fps.frames(media.duration))).font(.system(size: 10,design: .monospaced)).foregroundStyle(.secondary)
                                if let range = media.selection {
                                    Text("Marked \(session.fps.timecode((try? range.clipFrames(at: session.fps)) ?? 0))").font(.system(size: 10,design: .monospaced)).foregroundStyle(.secondary)
                                }
                            }
                        }.padding(.vertical,3).tag(media.id)
                        .onTapGesture(count: 2) { session.append(media.id) }
                        .onDrag { NSItemProvider(object: media.id.uuidString as NSString) }
                        .contextMenu {
                            Button("Open Source") { session.openSource(media.id) }
                            Button("Append to Timeline") { session.append(media.id) }
                            Button("Insert at Playhead") { session.append(media.id,atPlayhead: true,insert: true) }
                            Button("Overwrite at Playhead") { session.append(media.id,atPlayhead: true,overwrite: true) }
                            if media.kind == .video {
                                Button("Generate Proxy (720p H.264)") { session.generateMedia(media,mode: .proxy) }
                                Button("Generate Optimized (ProRes)") { session.generateMedia(media,mode: .optimized) }
                            }
                            Button("Relink Media…") { session.relink(media) }
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([media.url]) }
                        }
                    }
                }.listStyle(.sidebar).scrollContentBackground(.hidden).background(EditorStyle.content)
            }
            Divider()
            HStack {
                Button("Open Source") { if let id = session.selectedAsset { session.openSource(id) } }.font(.system(size: 10)).buttonStyle(.plain).disabled(session.selectedAsset == nil)
                Spacer()
                Button { if let id = session.selectedAsset { session.append(id) } } label: { Image(systemName: "plus.rectangle.on.rectangle") }
                    .buttonStyle(.plain).disabled(session.selectedAsset == nil).help("Append selected media")
            }.padding(.horizontal,12).frame(height: 32)
        }.background(EditorStyle.panel)
    }
}
