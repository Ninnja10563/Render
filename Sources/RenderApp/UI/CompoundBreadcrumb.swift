import SwiftUI

struct CompoundBreadcrumb: View {
    @ObservedObject var session: EditorSession
    var body: some View {
        HStack(spacing: 7) {
            Button(session.document.name) { session.returnToTimeline(depth: 0) }
            ForEach(Array(session.compoundPath.enumerated()),id: \.element) { index,id in
                Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(.tertiary)
                let name = session.document.compounds?.first(where: { $0.id == id })?.name ?? "Compound"
                if index == session.compoundPath.count - 1 { Text(name).fontWeight(.medium) }
                else { Button(name) { session.returnToTimeline(depth: index + 1) } }
            }
            Spacer()
            Text("Compound timeline").foregroundStyle(.secondary).lineLimit(1)
                .help("Editing this source updates every instance. Save and export include the full project.")
        }.buttonStyle(.plain).font(.system(size: 11)).padding(.horizontal,12).frame(height: 29).background(EditorStyle.panel)
        Divider()
    }
}
