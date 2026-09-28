import SwiftUI
import RenderCore

struct MulticamSetupView: View {
    @ObservedObject var session: EditorSession
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Multicam"
    @State private var angles: [CameraAngle] = []
    private var media: [MediaAsset] { session.project.assets.filter { $0.kind == .video } }
    var body: some View {
        VStack(alignment: .leading,spacing: 16) {
            Text("Create Multicam Source").font(.headline)
            TextField("Name",text: $name)
            ForEach(Array(angles.enumerated()),id: \.element.id) { index,angle in
                HStack {
                    TextField("Camera name",text: $angles[index].name).frame(width: 100)
                    Picker("Media",selection: $angles[index].assetID) { ForEach(media) { Text($0.name).tag($0.id) } }.labelsHidden().disabled(index == 0)
                    TextField("Offset",value: $angles[index].offset,format: .number.precision(.fractionLength(0...3))).frame(width: 65).disabled(index == 0)
                    if index > 1 { Button { angles.remove(at: index) } label: { Image(systemName: "minus") }.buttonStyle(.plain) }
                }
            }
            Button("Add Camera") { if let asset = media.first(where: { item in !angles.contains(where: { $0.assetID == item.id }) }) { angles.append(CameraAngle(name: "Camera \(angles.count + 1)",assetID: asset.id)) } }.disabled(angles.count >= min(16,media.count))
            Text("Offsets are seconds in camera source time at reference time zero. A positive offset means that camera was already recording when the reference began. Angles keep their original media; audio follows the chosen camera.").font(.caption).foregroundStyle(.secondary)
            Text("Use trimmed clips whose source ranges are available in each camera. Angle cuts pause playback while the timeline rebuilds.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel",role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") {
                    guard let clip = session.selectedClip else { return }
                    session.perform(.makeMulticam(clip: clip.id,MulticamSource(name: name,angles: angles)))
                    if session.project.clip(clip.id)?.multicam != nil { session.showAngles = true; dismiss() }
                }.disabled(angles.count < 2 || name.isEmpty).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 560)
            .onAppear {
                guard let clip = session.selectedClip, let first = media.first(where: { $0.id == clip.assetID }) else { return }
                angles = [CameraAngle(name: "Camera 1",assetID: first.id)]
                if let second = media.first(where: { $0.id != first.id }) { angles.append(CameraAngle(name: "Camera 2",assetID: second.id)) }
                name = clip.name
            }
    }
}

struct MulticamInspectorView: View {
    @ObservedObject var session: EditorSession
    let clip: TimelineClip
    var body: some View {
        if let membership = clip.multicam, let source = session.project.multicamSources?.first(where: { $0.id == membership.sourceID }) {
            VStack(alignment: .leading,spacing: 8) {
                Text(source.name).font(.system(size: 11,weight: .semibold))
                Picker("Camera",selection: Binding(get: { membership.angleID },set: { session.switchCamera($0,cut: false) })) {
                    ForEach(source.angles) { Text($0.name).tag($0.id) }
                }.font(.system(size: 10))
                Button("Show Camera Angles") { session.showAngles = true }
                Text("Choose here to replace this segment. Click an angle in the viewer to cut at the playhead.").font(.caption).foregroundStyle(.secondary)
                Divider()
            }
        }
    }
}

extension EditorSession {
    func switchCamera(_ angle: UUID,cut: Bool) {
        guard let clip = selectedClip, let location = project.location(clip.id) else { return }
        let trackID = project.tracks[location.track].id, frame = playhead
        perform(.switchAngle(clip: clip.id,angle: angle,at: cut ? frame : nil))
        if cut, let segment = project.tracks.first(where: { $0.id == trackID })?.clips.first(where: { $0.start == frame && $0.multicam?.angleID == angle }) { selection = [segment.id] }
    }
}
