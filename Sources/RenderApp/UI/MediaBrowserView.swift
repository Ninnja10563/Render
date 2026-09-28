import SwiftUI
import RenderCore

struct MediaBrowserView: View {
    @ObservedObject var session: EditorSession
    @State private var search = ""
    @AppStorage("Render.MediaGrid") private var grid = true
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
            } else if grid {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 94),spacing: 12)],alignment: .leading,spacing: 14) {
                        ForEach(filtered) { media in
                            Button { session.selectedAsset = media.id } label: {
                                VStack(alignment: .leading,spacing: 4) {
                                    ZStack {
                                        Color.black
                                        if let image = session.thumbnails[media.id] { Image(nsImage: image).resizable().scaledToFit() }
                                        else { Image(systemName: media.kind == .audio ? "waveform" : "film").foregroundStyle(.secondary) }
                                    }.frame(height: 58).clipped()
                                        .overlay { Rectangle().strokeBorder(session.selectedAsset == media.id ? Color.accentColor : .clear,lineWidth: 1) }
                                    Text(media.name).font(.system(size: 10)).lineLimit(1).frame(maxWidth: .infinity,alignment: .leading)
                                    Text(session.fps.timecode(session.fps.frames(media.duration)))
                                        .font(.system(size: 10,design: .monospaced)).foregroundStyle(.secondary)
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain)
                                .accessibilityLabel(media.name).accessibilityAddTraits(session.selectedAsset == media.id ? .isSelected : [])
                                .simultaneousGesture(TapGesture(count: 2).onEnded { session.append(media.id) })
                                .onDrag { NSItemProvider(object: media.id.uuidString as NSString) }
                                .contextMenu { mediaMenu(media) }
                        }
                    }.padding(10)
                }.background(EditorStyle.content)
            } else {
                List(selection: $session.selectedAsset) {
                    ForEach(filtered) { media in
                        HStack(spacing: 8) {
                            ZStack {
                                Color.black.opacity(0.2)
                                if let image = session.thumbnails[media.id] { Image(nsImage: image).resizable().scaledToFit() }
                                else { Image(systemName: media.kind == .audio ? "waveform" : "film").foregroundStyle(.secondary) }
                            }.frame(width: 64,height: 40).clipped()
                            VStack(alignment: .leading,spacing: 2) {
                                Text(media.name).font(.system(size: 11,weight: .regular)).lineLimit(1)
                                Text(media.kind == .audio ? "\(media.audioChannels) ch · \(media.codec)" : "\(media.width) × \(media.height) · \(media.codec)").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                Text(session.fps.timecode(session.fps.frames(media.duration))).font(.system(size: 10,design: .monospaced)).foregroundStyle(.secondary)
                                if let range = media.selection {
                                    Text("Marked \(session.fps.timecode((try? range.clipFrames(at: session.fps)) ?? 0))").font(.system(size: 10,design: .monospaced)).foregroundStyle(.secondary)
                                }
                            }
                        }.padding(.vertical,3).tag(media.id)
                        .onTapGesture(count: 2) { session.append(media.id) }
                        .onDrag { NSItemProvider(object: media.id.uuidString as NSString) }
                        .contextMenu { mediaMenu(media) }
                    }
                }.listStyle(.plain).scrollContentBackground(.hidden).background(EditorStyle.content)
            }
            Divider()
            HStack(spacing: 8) {
                Picker("Media layout",selection: $grid) {
                    Image(systemName: "square.grid.2x2").tag(true)
                    Image(systemName: "list.bullet").tag(false)
                }.pickerStyle(.segmented).labelsHidden().controlSize(.small).frame(width: 58).help("Thumbnail or list view")
                Button("Open Source") { if let id = session.selectedAsset { session.openSource(id) } }.font(.system(size: 10)).buttonStyle(.plain).disabled(session.selectedAsset == nil)
                Spacer()
                Button { if let id = session.selectedAsset { session.append(id) } } label: { Image(systemName: "plus.rectangle.on.rectangle") }
                    .buttonStyle(.plain).disabled(session.selectedAsset == nil).help("Append selected media")
            }.padding(.horizontal,12).frame(height: 32)
        }.background(EditorStyle.panel)
    }
    @ViewBuilder private func mediaMenu(_ media: MediaAsset) -> some View {
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
