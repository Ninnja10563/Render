import AppKit
import Combine
import Sparkle

/// Sparkle owns scheduling, preferences, signature validation and atomic installation.
/// Relaunch uses the normal application termination path, including save/export guards.
@MainActor
final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()
    @Published private(set) var canCheck = false
    @Published private(set) var automaticChecks = false
    @Published private(set) var automaticDownloads = false
    @Published private(set) var lastCheck: Date?
    private let controller: SPUStandardUpdaterController
    private var started = false

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: false,updaterDelegate: nil,userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$automaticChecks)
        controller.updater.publisher(for: \.automaticallyDownloadsUpdates).assign(to: &$automaticDownloads)
        controller.updater.publisher(for: \.lastUpdateCheckDate).assign(to: &$lastCheck)
    }
    func start() {
        guard !started,!CommandLine.arguments.contains("--smoke-test") else { return }
        started = true
        controller.startUpdater()
    }
    func check() { if canCheck { controller.checkForUpdates(nil) } }
    func setAutomaticChecks(_ enabled: Bool) { controller.updater.automaticallyChecksForUpdates = enabled }
    func setAutomaticDownloads(_ enabled: Bool) { controller.updater.automaticallyDownloadsUpdates = enabled }
}
