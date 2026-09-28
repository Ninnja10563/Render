import SwiftUI

/// Semantic surfaces adapt to the native appearance without adding decorative layers.
enum EditorStyle {
    static let panel = Color(nsColor: .windowBackgroundColor)
    static let content = Color(nsColor: .controlBackgroundColor)
    static let canvas = Color(nsColor: .textBackgroundColor)
    static let sectionFont = Font.system(size: 11,weight: .semibold)
    static let metadataFont = Font.system(size: 10)
}

struct PanelHeader<Actions: View>: View {
    let title: String
    let actions: Actions
    init(_ title: String,@ViewBuilder actions: () -> Actions) {
        self.title = title; self.actions = actions()
    }
    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 11,weight: .medium)).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 6)
            actions.font(.system(size: 11)).foregroundStyle(.secondary)
        }.buttonStyle(.plain).padding(.horizontal,10).frame(height: 32)
            .background(EditorStyle.panel)
            .overlay(alignment: .bottom) { Divider() }
    }
}

/// Shared lane geometry keeps mouse targeting and drag previews in step with the layout.
enum TimelineMetrics {
    static let laneHeight: CGFloat = 48
}
