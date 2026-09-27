import SwiftUI
import RenderMedia

struct BackgroundTasksButton: View {
    @ObservedObject var queue: BackgroundTasks
    @State private var showing = false
    var body: some View {
        Button { showing.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: "clock.arrow.circlepath")
                if queue.activeCount > 0 { Text("\(queue.activeCount)").monospacedDigit() }
            }
        }.help("Background Tasks")
            .popover(isPresented: $showing) {
                VStack(alignment: .leading,spacing: 12) {
                    HStack {
                        Text("Background Tasks").font(.headline)
                        Spacer()
                        Button("Clear Finished") { queue.clearFinished() }.controlSize(.mini)
                    }
                    if queue.tasks.isEmpty { Text("No background tasks.").foregroundStyle(.secondary) }
                    ScrollView {
                        LazyVStack(alignment: .leading,spacing: 14) {
                            ForEach(queue.tasks) { task in
                                VStack(alignment: .leading,spacing: 4) {
                                    HStack {
                                        Text("\(task.mode.label) · \(task.name)").lineLimit(1)
                                        Spacer()
                                        if task.state == .queued || task.state == .running {
                                            Button { queue.cancel(task.id) } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("Cancel task")
                                        }
                                    }
                                    if task.state == .running { ProgressView(value: Double(task.progress)).progressViewStyle(.linear) }
                                    Text(task.error ?? task.state.rawValue.capitalized).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                            }
                        }
                    }.frame(maxHeight: 300)
                    Text("Proxies use H.264 up to 720p. Optimized media uses ProRes at source size. Final export uses original files.").font(.caption).foregroundStyle(.secondary)
                }.padding(16).frame(width: 350).font(.system(size: 11))
            }
    }
}
