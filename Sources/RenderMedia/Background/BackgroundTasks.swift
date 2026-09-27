import Foundation
import Combine
import RenderCore

public enum BackgroundTaskState: String, Sendable { case queued, running, completed, cancelled, failed }
public struct BackgroundTaskInfo: Identifiable, Sendable {
    public let id: UUID
    public let assetID: UUID
    public let mode: PlaybackMediaMode
    public let name: String
    public var state: BackgroundTaskState = .queued
    public var progress: Float = 0
    public var error: String?
}

/// A bounded-concurrency media queue. Encoding runs in AVFoundation while UI progress is isolated here.
@MainActor
public final class BackgroundTasks: ObservableObject {
    @Published public private(set) var tasks: [BackgroundTaskInfo] = []
    public var activeCount: Int { tasks.filter { $0.state == .queued || $0.state == .running }.count }
    private struct Work {
        let id: UUID
        let media: MediaAsset
        let mode: PlaybackMediaMode
        let complete: (Result<MediaVariant,Error>) -> Void
    }
    private var pending: [Work] = []
    private var worker: Task<Void,Never>?
    private var activeID: UUID?
    private let transcoder = MediaTranscoder()
    private let folder: URL
    public init(folder: URL? = nil) {
        self.folder = folder ?? FileManager.default.urls(for: .applicationSupportDirectory,in: .userDomainMask)[0].appendingPathComponent("Render/Generated Media",isDirectory: true)
    }
    @discardableResult
    public func enqueue(_ media: MediaAsset,mode: PlaybackMediaMode,complete: @escaping (Result<MediaVariant,Error>) -> Void) -> UUID {
        if let duplicate = tasks.first(where: { $0.assetID == media.id && $0.mode == mode && ($0.state == .queued || $0.state == .running) }) { return duplicate.id }
        let id = UUID()
        tasks.append(BackgroundTaskInfo(id: id,assetID: media.id,mode: mode,name: media.name))
        pending.append(Work(id: id,media: media,mode: mode,complete: complete))
        if worker == nil { worker = Task { await drain() } }
        return id
    }
    public func cancel(_ id: UUID) {
        if activeID == id { transcoder.cancel(); return }
        if let index = pending.firstIndex(where: { $0.id == id }) {
            let work = pending.remove(at: index); update(id) { $0.state = .cancelled }; work.complete(.failure(CancellationError()))
        }
    }
    public func cancelAll() {
        for id in pending.map(\.id) { cancel(id) }
        if let activeID { cancel(activeID) }
    }
    public func waitUntilIdle() async {
        while worker != nil { try? await Task.sleep(nanoseconds: 50_000_000) }
    }
    public func clearFinished() { tasks.removeAll { $0.state != .queued && $0.state != .running } }
    private func update(_ id: UUID,_ change: (inout BackgroundTaskInfo) -> Void) {
        if let index = tasks.firstIndex(where: { $0.id == id }) { change(&tasks[index]) }
    }
    private func drain() async {
        while !pending.isEmpty {
            let work = pending.removeFirst(); activeID = work.id
            update(work.id) { $0.state = .running }
            do {
                let result = try await transcoder.generate(work.media,mode: work.mode,in: folder) { [weak self] value in self?.update(work.id) { $0.progress = value } }
                update(work.id) { $0.state = .completed; $0.progress = 1 }
                work.complete(.success(result))
            } catch {
                update(work.id) { $0.state = error is CancellationError ? .cancelled : .failed; $0.error = error is CancellationError ? nil : error.localizedDescription }
                work.complete(.failure(error))
            }
            activeID = nil
            while tasks.count > 100 {
                guard let index = tasks.firstIndex(where: { $0.state != .running && $0.state != .queued }) else { break }
                tasks.remove(at: index)
            }
        }
        worker = nil
    }
}
