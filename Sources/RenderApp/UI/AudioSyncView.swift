import SwiftUI
import RenderCore
import RenderMedia

struct AudioSyncView: View {
    @ObservedObject var session: EditorSession
    @Environment(\.dismiss) private var dismiss
    @State private var referenceID: UUID?
    @State private var match: AudioSyncMatch?
    @State private var snapshot: RenderProject?
    @State private var task: Task<Void,Never>?
    @State private var error: String?
    private var clips: [TimelineClip] {
        session.project.tracks.flatMap(\.clips).filter { session.selection.contains($0.id) }.sorted { $0.start == $1.start ? $0.id.uuidString < $1.id.uuidString : $0.start < $1.start }
    }
    private var reference: TimelineClip? { clips.first { $0.id == referenceID } ?? clips.first }
    private var target: TimelineClip? { clips.first { $0.id != reference?.id } }
    private var destination: Int64? {
        guard let match, let reference else { return nil }
        return reference.start + session.fps.frames(Double(match.offset) / 100)
    }
    var body: some View {
        VStack(alignment: .leading,spacing: 18) {
            Text("Synchronize Audio").font(.headline)
            Text("Align two clips using their shared recorded sound. The reference stays in place.").font(.subheadline).foregroundStyle(.secondary)
            Picker("Reference",selection: Binding(get: { reference?.id },set: { referenceID = $0; match = nil; error = nil })) {
                ForEach(clips) { clip in Text(clip.name).tag(Optional(clip.id)) }
            }.disabled(task != nil)
            if let target { LabeledContent("Move",value: target.name) }
            Text("Analyzes up to two minutes from each clip’s in-point, searching offsets within 30 seconds. Clips must be on separate unlocked tracks at 100% speed. Use a traditional timeline for this alignment.").font(.caption).foregroundStyle(.secondary)
            if task != nil { HStack { ProgressView().controlSize(.small); Text("Comparing recorded audio…") } }
            if let match, let destination, let target {
                LabeledContent("Match",value: "\(Int((match.correlation * 100).rounded()))% correlation")
                LabeledContent("Move by",value: String(format: "%+.3f seconds",session.fps.seconds(destination - target.start)))
                LabeledContent("New start",value: session.fps.timecode(destination))
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button("Cancel",role: .cancel) { task?.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Analyze") { analyze() }.disabled(task != nil || clips.count != 2)
                Button("Apply Alignment") { apply() }.keyboardShortcut(.defaultAction).disabled(match == nil || task != nil || snapshot != session.project)
            }
        }.padding(24).frame(width: 470)
            .onDisappear { task?.cancel() }
    }
    private func analyze() {
        guard let reference, let target, let a = session.project.assets.first(where: { $0.id == reference.assetID }), let b = session.project.assets.first(where: { $0.id == target.assetID }),
              let r = session.project.location(reference.id), let t = session.project.location(target.id) else {
            error = "Select two media clips containing audio."; return
        }
        guard r.track != t.track, !session.project.tracks[r.track].locked, !session.project.tracks[t.track].locked,
              session.project.storyline?.enabled != true, target.connection == nil else {
            error = "Use separate unlocked tracks in traditional mode and disconnect the moving clip from its storyline."; return
        }
        match = nil; error = nil; snapshot = session.project
        let rate = session.fps
        task = Task {
            defer { task = nil }
            do {
                let result = try await AudioSyncAnalyzer().analyze(reference: a,referenceClip: reference,target: b,targetClip: target,rate: rate)
                try Task.checkCancellation()
                guard snapshot == session.project else { throw RenderError.invalid("The project changed during analysis. Analyze again.") }
                let newStart = reference.start + rate.frames(Double(result.offset) / 100)
                guard newStart >= 0 else { throw RenderError.invalid("This alignment would place the moving clip before the timeline starts. Move the reference later, then analyze again.") }
                _ = try TimelineCommand.move(clips: [target.id],delta: newStart - target.start).applying(to: session.project)
                match = result
            } catch is CancellationError { } catch { self.error = error.localizedDescription }
        }
    }
    private func apply() {
        guard let target, let destination, snapshot == session.project else { return }
        session.perform(.move(clips: [target.id],delta: destination - target.start)); dismiss()
    }
}
