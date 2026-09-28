import Foundation

extension Notification.Name {
    static let renderCommitInspector = Notification.Name("app.render.commitInspector")
}

/// A synchronous request: save/close must see valid field drafts before snapshotting the project.
final class InspectorCommitRequest {
    var error: String?
}
