import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers
import RenderCore
import RenderMedia

@MainActor
final class EditorSession: ObservableObject {
    @Published var project = RenderProject()
    @Published var selection: Set<UUID> = []
    @Published var movePreview: Int64 = 0
    @Published var selectedRange: TimelineSelectionRange?
    @Published var selectedAsset: UUID?
    @Published var selectedTrack: UUID?
    @Published var playhead: Int64 = 0
    @Published var isPlaying = false
    @Published var isDirty = false
    @Published var errorMessage: String?
    @Published var activity: String?
    @Published var thumbnails: [UUID: NSImage] = [:]
    @Published var waveforms: [UUID: [Float]] = [:]
    @Published var pointsPerSecond: Double = 70
    @Published var snapping = true
    @Published var tool: EditingTool = .select
    @Published var showLibrary = true
    @Published var showInspector = true
    @Published var showTimeline = true
    @Published var showExport = false
    @Published var documentURL: URL?
    @Published var recentURLs: [URL] = []
    @Published var previewError: String?
    @Published var previewReady = false
    @Published var importing = false
    let player = AVPlayer()
    let history = UndoManager()
    let exporter = ExportService()
    let library = MediaLibrary()
    private let store = ProjectStore()
    private let builder = CompositionBuilder()
    private var savedProject = RenderProject()
    private var observer: Any?
    private var buildTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var generation = UUID()
    private var playbackObservation: NSKeyValueObservation?
    private var previewTasks: [UUID: Task<Void, Never>] = [:]
    private var clipboard: [ClipboardLane] = []
    private var clipboardProjectID: UUID?
    private var didStart = false
    var recoveryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Render/Recovery.renderproject")
    }
    var selectedClip: TimelineClip? { selection.count == 1 ? selection.first.flatMap { project.clip($0) } : nil }
    var selectedMedia: MediaAsset? { project.assets.first { $0.id == selectedAsset } }
    var fps: FrameRate { project.settings.frameRate }
    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }
    init() {
        savedProject = project
        history.groupsByEvent = false
        history.levelsOfUndo = 200
        recentURLs = (UserDefaults.standard.stringArray(forKey: "recentProjects") ?? []).map { URL(fileURLWithPath: $0) }
        player.actionAtItemEnd = .pause
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 60), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self, time.seconds.isFinite else { return }
                if self.player.rate != 0 { self.playhead = min(self.project.duration, max(0,self.fps.frames(time.seconds))) }
                self.isPlaying = self.player.rate != 0
            }
        }
    }
    func start() {
        guard !didStart else { return }; didStart = true
        guard !CommandLine.arguments.contains("--smoke-test"), FileManager.default.fileExists(atPath: recoveryURL.path) else { return }
        Task {
            do {
                let recovered = try await store.load(recoveryURL)
                let alert = NSAlert()
                alert.messageText = "Recover unsaved edits?"
                alert.informativeText = "Render found a recovery copy of “\(recovered.name)”. Your original project file has not been changed."
                alert.addButton(withTitle: "Recover"); alert.addButton(withTitle: "Discard Recovery")
                if alert.runModal() == .alertFirstButtonReturn {
                    install(recovered, url: nil); isDirty = true; savedProject = RenderProject()
                } else { try await store.remove(recoveryURL) }
            } catch { report(error) }
        }
    }
    func report(_ error: Error) {
        if error is CancellationError { return }
        errorMessage = error.localizedDescription
    }
    func perform(_ command: TimelineCommand) {
        do {
            let transaction = try ProjectTransaction(command, project: project)
            commit(transaction.after, name: transaction.name)
        } catch { report(error) }
    }
    func commit(_ next: RenderProject, name: String) {
        do { try next.validate() } catch { report(error); return }
        guard next != project else { return }
        let previous = project
        let explicitGroup = !history.isUndoing && !history.isRedoing
        if explicitGroup { history.beginUndoGrouping() }
        history.registerUndo(withTarget: self) { target in
            // UndoManager is owned and invoked exclusively by this main-actor session.
            MainActor.assumeIsolated { target.commit(previous, name: name) }
        }
        history.setActionName(name)
        if explicitGroup { history.endUndoGrouping() }
        project = next; isDirty = project != savedProject
        selection = selection.filter { project.clip($0) != nil }
        scheduleRecovery()
        if previous.tracks != next.tracks || previous.settings != next.settings ||
            previous.assets.contains(where: { old in next.assets.first(where: { $0.id == old.id }) != old }) { rebuild() }
    }
    func undo() { history.undo(); objectWillChange.send() }
    func redo() { history.redo(); objectWillChange.send() }
    func scheduleRecovery() {
        guard !CommandLine.arguments.contains("--smoke-test") else { return }
        recoveryTask?.cancel()
        let snapshot = project
        recoveryTask = Task {
            do {
                try await Task.sleep(nanoseconds: 750_000_000)
                try Task.checkCancellation()
                try await store.save(snapshot, to: recoveryURL)
            } catch { if !(error is CancellationError) { report(error) } }
        }
    }
    func rebuild() {
        generation = UUID(); let token = generation
        buildTask?.cancel(); pause(); previewReady = false
        let snapshot = project
        previewError = nil
        guard snapshot.duration > 0 else { player.replaceCurrentItem(with: nil); playhead = 0; return }
        buildTask = Task {
            do {
                let prepared = try await builder.build(snapshot)
                try Task.checkCancellation()
                guard token == generation else { return }
                let item = prepared.playerItem()
                player.replaceCurrentItem(with: item)
                playbackObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                    Task { @MainActor in
                        guard let self, self.player.currentItem === item else { return }
                        if item.status == .failed { self.previewError = item.error?.localizedDescription ?? "Playback failed."; self.previewReady = false }
                    }
                }
                previewReady = true
                seek(min(playhead, max(0,project.duration - 1)))
            } catch {
                guard token == generation, !(error is CancellationError) else { return }
                player.replaceCurrentItem(with: nil); previewError = error.localizedDescription
            }
        }
    }
    func seek(_ frame: Int64) {
        playhead = min(max(0,frame),max(0,project.duration - 1))
        player.currentItem?.cancelPendingSeeks()
        player.seek(to: CMTime(value: playhead * Int64(fps.denominator), timescale: fps.numerator), toleranceBefore: .zero, toleranceAfter: .zero)
    }
    func pause() { player.pause(); isPlaying = false }
    func togglePlayback() {
        guard previewReady else { return }
        if player.rate != 0 { pause() }
        else { if playhead >= project.duration - 1 { seek(0) }; player.play(); isPlaying = true }
    }
    func shuttle(_ direction: Float) {
        guard previewReady else { return }
        if direction < 0, player.currentItem?.canPlayReverse != true { seek(playhead - 1); return }
        let current = player.rate
        player.rate = current * direction > 0 ? direction * min(abs(current) * 2,4) : direction
        isPlaying = true
    }
    func selectClip(_ id: UUID, extend: Bool = false) {
        NSApp.keyWindow?.makeFirstResponder(nil)
        selectedRange = nil
        if extend { if selection.contains(id) { selection.remove(id) } else { selection.insert(id) } }
        else { selection = [id] }
        if let location = project.location(id) { selectedTrack = project.tracks[location.track].id }
    }
    func split() {
        let ids = selection.isEmpty ? Set(project.tracks.filter { !$0.locked }.flatMap(\.clips).filter { $0.start < playhead && $0.end > playhead }.map(\.id)) : selection
        perform(.split(clips: ids, at: playhead))
    }
    func delete(ripple: Bool = false) {
        if let range = selectedRange {
            perform(.deleteRange(track: range.trackID,start: range.start,end: range.end,ripple: ripple)); selectedRange = nil
        } else { perform(.delete(clips: selection, ripple: ripple)) }
    }
    func copy() {
        clipboard = project.tracks.compactMap { track in
            let selected = track.clips.filter { selection.contains($0.id) }
            return selected.isEmpty ? nil : ClipboardLane(trackID: track.id,clips: selected)
        }
        clipboardProjectID = project.id
    }
    func cut() {
        guard !project.tracks.contains(where: { $0.locked && $0.clips.contains(where: { selection.contains($0.id) }) }) else { errorMessage = "Unlock selected tracks before cutting."; return }
        copy(); delete()
    }
    func paste() {
        guard clipboardProjectID == project.id, !clipboard.isEmpty, let track = selectedTrack ?? project.tracks.first?.id else { return }
        if clipboard.count == 1, let lane = clipboard.first { perform(.paste(clips: lane.clips, track: track, at: playhead)) }
        else { perform(.pasteLanes(clipboard,at: playhead)) }
    }
    func append(_ assetID: UUID, atPlayhead: Bool = false, insert: Bool = false, overwrite: Bool = false) {
        guard let media = project.assets.first(where: { $0.id == assetID }) else { return }
        let kind: TrackKind = media.kind == .audio ? .audio : .video
        guard let track = project.tracks.first(where: { $0.id == selectedTrack && $0.kind == kind }) ?? project.tracks.last(where: { $0.kind == kind && !$0.locked }) else { return }
        let at = atPlayhead ? playhead : (track.clips.map(\.end).max() ?? 0)
        if overwrite { perform(.overwrite(asset: assetID,track: track.id,at: at)) }
        else { perform(insert ? .insert(asset: assetID, track: track.id, at: at) : .append(asset: assetID, track: track.id, at: at)) }
    }
    func importPanel() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.movie,.audio,.image]
        panel.prompt = "Import"
        if panel.runModal() == .OK { importMedia(panel.urls) }
    }
    func importMedia(_ urls: [URL]) {
        guard !importing else { errorMessage = "Wait for the current import to finish."; return }
        let projectID = project.id
        importing = true
        Task {
            var failures: [String] = []
            defer { importing = false; activity = nil }
            for (index,url) in urls.enumerated() {
                guard project.id == projectID else { break }
                if project.assets.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) { continue }
                activity = "Importing \(index + 1) of \(urls.count) · \(url.lastPathComponent)"
                do {
                    let media = try await library.analyze(url)
                    guard project.id == projectID else { break }
                    perform(.addAsset(media)); selectedAsset = media.id
                    loadPreview(media)
                } catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            }
            if !failures.isEmpty { errorMessage = failures.joined(separator: "\n") }
        }
    }
    func loadPreview(_ media: MediaAsset) {
        let projectID = project.id
        previewTasks[media.id]?.cancel()
        previewTasks[media.id] = Task {
            defer { if project.id == projectID { previewTasks[media.id] = nil } }
            if let image = try? await library.thumbnail(media), !Task.isCancelled, project.id == projectID { thumbnails[media.id] = NSImage(cgImage: image, size: .zero) }
            guard !Task.isCancelled else { return }
            if media.audioChannels > 0, let peaks = try? await library.waveform(media), !Task.isCancelled, project.id == projectID { waveforms[media.id] = peaks }
        }
    }
    func relink(_ media: MediaAsset) {
        let panel = NSOpenPanel(); panel.message = "Locate the original source for \(media.name)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let projectID = project.id
        Task {
            do {
                var replacement = try await library.analyze(url)
                guard project.id == projectID else { return }
                guard replacement.kind == media.kind else { throw RenderError.invalid("Replacement media must have the same type.") }
                replacement.id = media.id
                var next = project
                guard let index = next.assets.firstIndex(where: { $0.id == media.id }) else { return }
                next.assets[index] = replacement; try next.validate()
                await library.invalidate(media.url)
                thumbnails[media.id] = nil; waveforms[media.id] = nil
                commit(next, name: "Relink Media"); loadPreview(replacement)
            } catch { report(error) }
        }
    }
    func save(asNew: Bool = false) async -> Bool {
        var target = asNew ? nil : documentURL
        if target == nil {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType(exportedAs: "app.render.project", conformingTo: .json)]
            panel.nameFieldStringValue = project.name + ".renderproject"
            guard panel.runModal() == .OK, let url = panel.url else { return false }
            target = url
        }
        guard let target else { return false }
        let projectID = project.id
        var snapshot = project; snapshot.name = target.deletingPathExtension().lastPathComponent
        do {
            try await store.save(snapshot, to: target)
            guard project.id == projectID else { return true }
            documentURL = target; project.name = snapshot.name; savedProject = snapshot; isDirty = project != snapshot
            addRecent(target)
            if !isDirty { recoveryTask?.cancel(); try await store.remove(recoveryURL) }
            return true
        } catch { report(error); return false }
    }
    func confirmDiscard() async -> Bool {
        guard isDirty else { return true }
        let alert = NSAlert(); alert.messageText = "Save changes to “\(project.name)”?"
        alert.informativeText = "Your unsaved edits will be lost if you don’t save."
        alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Don’t Save")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return await save()
        case .alertThirdButtonReturn:
            recoveryTask?.cancel()
            do { try await store.remove(recoveryURL); return true } catch { report(error); return false }
        default: return false
        }
    }
    func newProject() {
        Task { if await confirmDiscard() { install(RenderProject(), url: nil) } }
    }
    func openPanel() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(exportedAs: "app.render.project", conformingTo: .json),.json]
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }
    func open(_ url: URL) {
        Task {
            // Decode before asking to replace the current document.
            do {
                let loaded = try await store.load(url)
                guard await confirmDiscard() else { return }
                install(loaded, url: url); addRecent(url)
            } catch { report(error) }
        }
    }
    func duplicate() {
        Task {
            guard await confirmDiscard() else { return }
            var copy = project; copy.id = UUID(); copy.name += " Copy"
            install(copy, url: nil); savedProject = RenderProject(); isDirty = true; scheduleRecovery()
        }
    }
    private func install(_ value: RenderProject, url: URL?) {
        recoveryTask?.cancel(); history.removeAllActions()
        previewTasks.values.forEach { $0.cancel() }; previewTasks.removeAll()
        project = value; savedProject = value; documentURL = url
        selection = []; selectedRange = nil; selectedAsset = nil; selectedTrack = nil; playhead = 0; isDirty = false
        thumbnails = [:]; waveforms = [:]; clipboard = []; clipboardProjectID = nil
        rebuild()
        for asset in project.assets { loadPreview(asset) }
    }
    private func addRecent(_ url: URL) {
        recentURLs.removeAll { $0 == url }; recentURLs.insert(url,at: 0); recentURLs = Array(recentURLs.prefix(12))
        UserDefaults.standard.set(recentURLs.map(\.path), forKey: "recentProjects")
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }
    func snap(_ frame: Int64, excluding ids: Set<UUID> = []) -> Int64 {
        guard snapping else { return max(0,frame) }
        let targets = [Int64(0),playhead] + project.markers.map(\.frame) + project.tracks.flatMap(\.clips).filter { !ids.contains($0.id) }.flatMap { [$0.start,$0.end] }
        return max(0,TimelineSnap.frame(frame, targets: targets, threshold: max(1,Int64(8 / pointsPerSecond * fps.value))))
    }
    func setProperty(_ key: String, value: Double) {
        guard let clip = selectedClip else { return }
        var p = clip.properties
        switch key { case "x": p.x = value; case "y": p.y = value; case "scale": p.scale = value; case "rotation": p.rotation = value; case "opacity": p.opacity = value; case "volume": p.volume = value; default: return }
        if var curve = p.animations[key], !curve.keys.isEmpty {
            let frame = max(0,min(clip.duration - 1,playhead - clip.start)) + clip.animationOffset
            curve.set(Keyframe(frame: frame,value: value)); p.animations[key] = curve
        }
        perform(.properties(clip: clip.id, p))
    }
    func toggleKeyframe(_ key: String) {
        guard let clip = selectedClip else { return }
        var p = clip.properties
        let frame = max(0,min(clip.duration - 1,playhead - clip.start)) + clip.animationOffset
        var curve = p.animations[key] ?? AnimationCurve()
        if curve.keys.contains(where: { $0.frame == frame }) { curve.keys.removeAll { $0.frame == frame } }
        else { curve.set(Keyframe(frame: frame,value: p.value(key,at: Double(frame)))) }
        p.animations[key] = curve
        perform(.properties(clip: clip.id,p))
    }
}

enum EditingTool: String, CaseIterable {
    case select = "Selection", blade = "Blade", trim = "Trim", ripple = "Ripple", roll = "Roll", slip = "Slip", slide = "Slide", range = "Range", zoom = "Zoom"
    var symbol: String {
        switch self {
        case .range: return "selection.pin.in.out"
        case .zoom: return "plus.magnifyingglass"
        case .select: return "cursorarrow"
        case .blade: return "scissors"
        case .trim: return "arrow.left.and.right"
        case .ripple: return "arrow.right.to.line"
        case .roll: return "arrow.left.and.right.righttriangle.left.righttriangle.right"
        case .slip: return "arrow.left.and.right.square"
        case .slide: return "rectangle.and.arrow.up.right.and.arrow.down.left"
        }
    }
}

struct TimelineSelectionRange {
    var trackID: UUID
    var start: Int64
    var end: Int64
}
