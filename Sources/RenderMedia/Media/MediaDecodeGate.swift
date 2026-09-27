import Foundation

/// Bounds simultaneous image decoders. Cancelled waiters release their slot before creating a decoder.
actor MediaDecodeGate {
    private let limit: Int
    private var active = 0
    private var waiting: [CheckedContinuation<Void,Never>] = []
    init(limit: Int = 2) { self.limit = limit }
    func acquire() async {
        if active < limit { active += 1; return }
        await withCheckedContinuation { waiting.append($0) }
    }
    func release() {
        if waiting.isEmpty { active -= 1 }
        else { waiting.removeFirst().resume() }
    }
}
