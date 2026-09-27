import SwiftUI
import UniformTypeIdentifiers
import RenderCore
import RenderMedia

struct ExportView: View {
    @ObservedObject var session: EditorSession
    @ObservedObject var exporter: ExportService
    @Environment(\.dismiss) private var dismiss
    @State private var codec = ExportCodec.h264
    @State private var width = 1920
    @State private var height = 1080
    @State private var fps = 30
    @State private var custom = false
    @State private var finished: URL?
    @State private var failure: String?
    var body: some View {
        VStack(alignment: .leading,spacing: 22) {
            HStack { Text("Export \(session.project.name)").font(.system(size: 18,weight: .semibold)); Spacer(); if !exporter.isExporting { Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain) } }
            if let finished {
                Label("Export complete",systemImage: "checkmark.circle").foregroundStyle(.green)
                Text(finished.path).font(.system(size: 11)).textSelection(.enabled)
                HStack { Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([finished]) }; Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
            } else {
                Form {
                    Picker("Codec",selection: $codec) { ForEach(ExportCodec.allCases,id: \.self) { Text($0.rawValue).tag($0) } }
                    Picker("Resolution",selection: $width) { Text("720p").tag(1280); Text("1080p").tag(1920); Text("1440p").tag(2560); Text("4K UHD").tag(3840) }.disabled(custom)
                    Toggle("Custom dimensions",isOn: $custom)
                    if custom {
                        TextField("Width",value: $width,format: .number)
                        TextField("Height",value: $height,format: .number)
                    }
                    Picker("Frame rate",selection: $fps) { Text("Project frame rate").tag(0); ForEach([24,25,30,50,60],id: \.self) { Text("\($0) fps").tag($0) } }
                    LabeledContent("Quality",value: "Highest quality · codec-managed bitrate")
                    LabeledContent("Duration",value: session.fps.timecode(session.project.duration))
                }.disabled(exporter.isExporting)
                Text("Export uses original media and the same compositor as the viewer. Existing files and source media are never overwritten.").font(.system(size: 11)).foregroundStyle(.secondary)
                if exporter.isExporting {
                    ProgressView(value: Double(exporter.progress))
                    HStack {
                        Text("\(Int(exporter.progress * 100))% · \(Int(exporter.elapsed))s elapsed")
                        Spacer()
                        if exporter.progress > 0.02 { Text("About \(Int(exporter.elapsed * Double(1 - exporter.progress) / Double(exporter.progress)))s remaining") }
                    }.font(.system(size: 10)).foregroundStyle(.secondary)
                }
                if let failure { Text(failure).font(.system(size: 11)).foregroundStyle(.red).textSelection(.enabled) }
                HStack {
                    Button(exporter.isExporting ? "Cancel Export" : "Cancel") { if exporter.isExporting { exporter.cancel() } else { dismiss() } }
                    Spacer()
                    Button("Export…",action: begin).buttonStyle(.borderedProminent).disabled(exporter.isExporting).keyboardShortcut(.defaultAction)
                }
            }
        }.padding(26).frame(width: 470).interactiveDismissDisabled(exporter.isExporting)
            .onAppear { width = session.project.settings.width; height = session.project.settings.height; fps = 0 }
            .onChange(of: width) { _,new in if !custom { height = new * 9 / 16 } }
    }
    func begin() {
        failure = nil
        var configuration = ExportConfiguration()
        configuration.codec = codec; configuration.width = width; configuration.height = height
        configuration.frameRate = fps == 0 ? session.fps : FrameRate(Int32(fps))
        do { try configuration.validate() } catch { failure = error.localizedDescription; return }
        let panel = NSSavePanel(); panel.allowedContentTypes = codec == .proRes ? [.quickTimeMovie] : [.mpeg4Movie]
        panel.nameFieldStringValue = session.project.name + (codec == .proRes ? ".mov" : ".mp4")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let project = session.project
        Task {
            do { try await exporter.export(project: project,configuration: configuration,to: url); finished = url }
            catch { failure = error is CancellationError ? "Export cancelled. No incomplete file was published." : error.localizedDescription }
        }
    }
}
