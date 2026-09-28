import SwiftUI
import RenderCore

struct SourceViewer: View {
    @ObservedObject var session: EditorSession
    @ObservedObject private var source: SourceMonitor
    init(session: EditorSession) { self.session = session; source = session.sourceMonitor }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(source.asset?.name ?? "Select source media").font(.system(size: 11,weight: .medium)).lineLimit(1)
                Spacer()
                Text("SOURCE · Original").font(.system(size: 9)).foregroundStyle(.secondary)
            }.padding(.horizontal,12).frame(height: 28)
            ZStack {
                Color.black
                if let image = source.still { Image(decorative: image,scale: 1).resizable().scaledToFit() }
                else if source.asset?.kind == .audio {
                    if let id = source.asset?.id,let peaks = session.waveforms[id],!peaks.isEmpty {
                        Canvas { context,size in
                            var path = Path()
                            for x in stride(from: 0.0,to: size.width,by: 2) {
                                let index = min(peaks.count - 1,Int(x / max(1,size.width) * Double(peaks.count)))
                                let amplitude = CGFloat(peaks[index]) * size.height * 0.4
                                path.move(to: CGPoint(x: x,y: size.height / 2 - amplitude)); path.addLine(to: CGPoint(x: x,y: size.height / 2 + amplitude))
                            }
                            context.stroke(path,with: .color(.gray),lineWidth: 1)
                            let x = Double(source.frame) / Double(source.totalFrames) * size.width
                            context.fill(Path(CGRect(x: x,y: 0,width: 1,height: size.height)),with: .color(.white))
                        }.padding(20)
                    } else { Image(systemName: "waveform").font(.system(size: 32,weight: .light)).foregroundStyle(.gray) }
                } else if source.asset != nil { PlayerSurface(player: source.player) }
                if let error = source.error { Text(error).foregroundStyle(.white).font(.system(size: 12)).multilineTextAlignment(.center).padding(20).background(.black.opacity(0.8)) }
                else if source.asset != nil && !source.ready { ProgressView("Opening source…").tint(.white).foregroundStyle(.white) }
                else if source.asset == nil { Text("Select media in the browser, then choose Open Source.").font(.system(size: 12)).foregroundStyle(.gray) }
            }.frame(maxWidth: .infinity,maxHeight: .infinity).clipped()
            if source.asset != nil {
                VStack(spacing: 8) {
                    Slider(value: Binding(get: { Double(source.frame) },set: { source.seek(Int64($0.rounded())) }),in: 0...Double(max(1,source.totalFrames - 1)))
                        .controlSize(.mini).help("Scrub source media")
                    GeometryReader { geometry in
                        let duration = max(0.000001,source.asset?.duration ?? 1)
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.secondary.opacity(0.2))
                            Rectangle().fill(Color.accentColor)
                                .frame(width: geometry.size.width * (source.range.end - source.range.start) / duration)
                                .offset(x: geometry.size.width * source.range.start / duration)
                        }
                    }.frame(height: 3).help("Marked source range")
                    HStack(spacing: 14) {
                        Text(source.rate.timecode(source.frame)).font(.system(size: 11,design: .monospaced))
                        Spacer(minLength: 0)
                        Button { source.seek(source.frame - 1) } label: { Image(systemName: "backward.frame.fill") }.help("Previous source frame (←)")
                        Button { source.togglePlayback() } label: { Image(systemName: source.playing ? "pause.fill" : "play.fill") }.disabled(!source.ready || source.asset?.kind == .image).help("Play source range (Space)")
                        Button { source.seek(source.frame + 1) } label: { Image(systemName: "forward.frame.fill") }.help("Next source frame (→)")
                        Spacer(minLength: 0)
                        Button("Mark In") { session.markSource(incoming: true) }.help("Mark source in (I)")
                        Button("Mark Out") { session.markSource(incoming: false) }.help("Mark source out, including this frame (O)")
                    }.buttonStyle(.plain)
                    HStack(spacing: 10) {
                        Text("In \(source.rate.timecode(source.rate.frames(source.range.start)))  Out \(source.rate.timecode(max(0,source.rate.frames(source.range.end) - 1)))")
                            .font(.system(size: 9,design: .monospaced)).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button("Clear Marks") { session.clearSourceMarks() }.disabled(source.asset?.selection == nil)
                    }
                    HStack {
                        Text("Selected \(source.rate.timecode((try? source.range.clipFrames(at: source.rate)) ?? 0))").font(.system(size: 10,design: .monospaced)).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button("Append") { session.editSource() }
                        Button("Insert") { session.editSource(insert: true) }
                        Button("Overwrite") { session.editSource(overwrite: true) }
                    }
                    if source.reversePreview { Text("Reverse preview · Audio muted").font(.system(size: 9)).foregroundStyle(.secondary) }
                }.font(.system(size: 10)).controlSize(.small).padding(.horizontal,12).padding(.vertical,8)
            }
        }.onChange(of: session.selectedAsset) { _,id in if let id { session.openSource(id) } }
            .onDisappear { source.pause() }
    }
}
