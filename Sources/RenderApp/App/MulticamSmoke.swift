import Foundation
import RenderCore
import RenderMedia

extension EditorSession {
    func checkMulticamEditing(folder: URL,still: MediaAsset) async throws {
        var fixture = RenderProject(); fixture.settings.width = 320; fixture.settings.height = 180; fixture.assets = [still]
        fixture.tracks[0].clips = [TimelineClip(assetID: still.id,name: "Camera source",start: 0,duration: 60)]
        var config = ExportConfiguration(); config.width = 320; config.height = 180
        var cameras: [MediaAsset] = []
        for index in 1...2 {
            var brightness = Effect(kind: .brightness); brightness.amount = index == 1 ? 0 : 0.1
            fixture.tracks[0].clips[0].effects = [brightness]
            let url = folder.appendingPathComponent("Camera \(index).mp4")
            try await ExportService().export(project: fixture,configuration: config,to: url)
            let camera = try await library.analyze(url); cameras.append(camera); perform(.addAsset(camera)); loadPreview(camera)
        }
        perform(.addTrack(.video))
        guard let track = project.tracks.first else { throw RenderError.invalid("Multicam test track missing.") }
        perform(.append(asset: cameras[0].id,track: track.id,at: 0))
        guard let clip = project.tracks.first?.clips.first else { throw RenderError.invalid("Multicam test clip missing.") }
        let source = MulticamSource(name: "Camera edit",angles: cameras.enumerated().map { CameraAngle(name: "Camera \($0.offset + 1)",assetID: $0.element.id) })
        perform(.makeMulticam(clip: clip.id,source))
        selection = [clip.id]; seek(15)
        switchCamera(source.angles[1].id,cut: true)
        guard selectedClip?.multicam?.angleID == source.angles[1].id, selectedClip?.start == 15 else { throw RenderError.invalid("Camera cut did not select the new segment.") }
        let selected = selection
        undo(); redo(); selection = selected; showAngles = true
        guard project.tracks.first?.clips.count == 2 else { throw RenderError.invalid("Camera cut undo/redo failed.") }
        print("RENDER_MULTICAM_OK sources angle-cut undo redo viewer")
    }
}
