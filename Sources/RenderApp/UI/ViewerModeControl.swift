import AppKit
import SwiftUI

/// AppKit exposes per-segment enablement, including its native disabled appearance.
struct ViewerModeControl: NSViewRepresentable {
    @Binding var showingSource: Bool
    let sourceAvailable: Bool
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: ["Timeline","Source"],trackingMode: .selectOne,target: context.coordinator,action: #selector(Coordinator.select(_:)))
        control.controlSize = .small; control.segmentStyle = .rounded
        control.setAccessibilityLabel("Viewer")
        return control
    }
    func updateNSView(_ control: NSSegmentedControl,context: Context) {
        context.coordinator.parent = self
        control.selectedSegment = showingSource ? 1 : 0
        control.setEnabled(sourceAvailable,forSegment: 1)
    }
    final class Coordinator: NSObject {
        var parent: ViewerModeControl
        init(_ parent: ViewerModeControl) { self.parent = parent }
        @objc func select(_ sender: NSSegmentedControl) { parent.showingSource = sender.selectedSegment == 1 }
    }
}
