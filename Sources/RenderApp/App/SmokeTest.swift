import AppKit
import AVFoundation
import RenderCore

extension EditorSession {
    /// Runs only when explicitly requested by the packaging script; no user document is touched.
    func runSmokeTest(delegate: RenderAppDelegate) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Render-Smoke-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Composition test card.png")
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,pixelsWide: 1920,pixelsHigh: 1080,bitsPerSample: 8,samplesPerPixel: 4,hasAlpha: true,isPlanar: false,colorSpaceName: .deviceRGB,bytesPerRow: 0,bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor(calibratedRed: 0.08,green: 0.13,blue: 0.18,alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0,y: 0,width: 1920,height: 1080)).fill()
        let colors: [NSColor] = [.init(calibratedRed: 0.65,green: 0.84,blue: 0.82,alpha: 1),.init(calibratedRed: 0.33,green: 0.53,blue: 0.64,alpha: 1),.init(calibratedRed: 0.85,green: 0.54,blue: 0.36,alpha: 1)]
        for (index,color) in colors.enumerated() { color.setFill(); NSBezierPath(rect: NSRect(x: 220 + index * 500,y: 210,width: 440,height: 280)).fill() }
        NSString(string: "Render").draw(at: NSPoint(x: 220,y: 660),withAttributes: [.font: NSFont.systemFont(ofSize: 124,weight: .medium),.foregroundColor: NSColor.white])
        NSString(string: "COMPOSITION VALIDATION  /  1920 × 1080").draw(at: NSPoint(x: 230,y: 570),withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 26,weight: .regular),.foregroundColor: NSColor.lightGray])
        NSGraphicsContext.restoreGraphicsState()
        try bitmap.representation(using: .png,properties: [:])!.write(to: url)
        let asset = try await library.analyze(url)
        perform(.addAsset(asset))
        append(asset.id)
        try await checkKeyboardShortcuts(delegate: delegate,asset: asset)
        guard let original = project.tracks[0].clips.first else { throw RenderError.invalid("Smoke import did not produce a clip.") }
        selection = [original.id]
        seek(60); split()
        guard project.tracks[0].clips.count == 2 else { throw RenderError.invalid("Smoke split failed.") }
        undo()
        guard project.tracks[0].clips.count == 1 else { throw RenderError.invalid("Smoke undo failed.") }
        redo()
        guard project.tracks[0].clips.count == 2 else { throw RenderError.invalid("Smoke redo failed.") }
        perform(.roll(clip: original.id,boundary: 75))
        guard project.clip(original.id)?.duration == 75 else { throw RenderError.invalid("Smoke roll edit failed.") }
        undo()
        perform(.rippleTrim(clip: original.id,edge: .trailing,to: 45))
        guard project.duration == 135 else { throw RenderError.invalid("Smoke ripple trim failed.") }
        undo()
        perform(.deleteRange(track: project.tracks[0].id,start: 10,end: 20,ripple: false))
        guard project.tracks[0].clips.count == 3 else { throw RenderError.invalid("Smoke range delete failed.") }
        undo()
        selection = [original.id]
        setProperty("scale",value: 0.9)
        toggleKeyframe("opacity")
        let effect = Effect(kind: .exposure)
        perform(.effects(clip: original.id,[effect]))
        perform(.animation(clip: original.id,target: .effect(effect.id),edit: .set(frame: 0,value: 0)))
        perform(.animation(clip: original.id,target: .effect(effect.id),edit: .set(frame: 50,value: 0.2)))
        guard let key = project.clip(original.id)?.effects.first?.animation.keys.first else { throw RenderError.invalid("Effect keyframe missing.") }
        perform(.animation(clip: original.id,target: .effect(effect.id),edit: .interpolation([key.id],.easeInOut)))
        perform(.animation(clip: original.id,target: .effect(effect.id),edit: .move(key: key.id,to: 5)))
        undo()
        guard project.clip(original.id)?.effects.first?.animation.keys.first?.frame == 0 else { throw RenderError.invalid("Keyframe undo failed.") }
        var masked = Effect(kind: .saturation)
        masked.amount = 0.5; masked.mask = EffectMask()
        perform(.effects(clip: original.id,(project.clip(original.id)?.effects ?? []) + [masked]))
        guard project.clip(original.id)?.effects.last?.mask != nil else { throw RenderError.invalid("Mask command failed.") }
        undo(); redo()
        perform(.marker(.init(frame: 60,name: "Edit point")))
        var title = TitleContent(text: "Native titles, real timelines"); title.fontSize = 48
        perform(.addTitle(title,at: 0,duration: 60))
        guard let titleClip = project.tracks.first?.clips.first, titleClip.title != nil else { throw RenderError.invalid("Title creation failed.") }
        selection = [titleClip.id]; setProperty("y",value: -360)
        let captions = try SRTCodec.decode("1\n00:00:02,000 --> 00:00:03,000\nCaption validation\n",rate: fps)
        perform(.captions(captions)); undo(); redo()
        selection = [titleClip.id]
        guard let storylineTrack = project.tracks.first(where: { $0.clips.contains(where: { $0.id == original.id }) }) else { throw RenderError.invalid("Storyline track missing.") }
        perform(.storyline(enabled: true,track: storylineTrack.id))
        perform(.connection(clip: titleClip.id,anchor: original.id))
        perform(.move(clips: [original.id],delta: 150))
        guard project.clip(titleClip.id)?.start == project.clip(original.id)?.start else { throw RenderError.invalid("Connected title did not move with its anchor.") }
        undo()
        perform(.gap(track: storylineTrack.id,at: 60,duration: 15))
        guard project.duration == 165 else { throw RenderError.invalid("Explicit magnetic gap failed.") }
        undo()
        setProperty("cropLeft",value: 0.03,clipID: original.id)
        setProperty("scaleX",value: 0.95,clipID: original.id)
        guard project.clip(original.id)?.properties.geometry?.cropLeft == 0.03,
              project.clip(titleClip.id)?.properties.geometry == nil else { throw RenderError.invalid("Inspector property edit targeted the wrong selection.") }
        if let left = project.clip(original.id), let track = project.tracks.first(where: { $0.clips.contains(where: { $0.id == original.id }) }), let right = track.clips.first(where: { $0.start == left.end }) {
            perform(.transition(clip: left.id,ClipTransition(rightID: right.id,kind: .crossDissolve,duration: 20)))
            guard project.clip(left.id)?.transition != nil else { throw RenderError.invalid("Transition authoring failed.") }
            undo(); redo()
        }
        try await checkFocusedInspectorSave(clipID: original.id,folder: folder)
        try await checkMulticamEditing(folder: folder,still: asset)
        try await checkTimelineViewport()
        try await checkTrackDragging(still: asset)
        try await checkCompoundEditing(folder: folder,still: asset)
        try await checkAudioMeterPlayback(folder: folder)
        try await checkAudioEffectPlayback(folder: folder)
        try await checkSourceMonitor(folder: folder)
        showAngles = false
        selection = Set(project.tracks.flatMap(\.clips).map(\.id))
        createCompound(name: "Opening Scene")
        guard let compound = selectedClip?.compoundID else { throw RenderError.invalid("Workspace compound creation failed.") }
        openCompound(compound); selectClip(original.id)
        try await checkWorkspaceControls()
        selectedAsset = asset.id
        if let image = try await library.thumbnail(asset) { thumbnails[asset.id] = NSImage(cgImage: image,size: .zero) }
        let deadline = Date().addingTimeInterval(15)
        while !previewReady || player.currentItem?.status != .readyToPlay {
            if let error = previewError { throw RenderError.invalid(error) }
            guard Date() < deadline else { throw RenderError.invalid("Playback never became ready during launch validation.") }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        try await checkReversePreview()
        try await captureUIReview()
        seek(30); togglePlayback()
        let playingDeadline = Date().addingTimeInterval(5)
        while player.timeControlStatus != .playing || player.currentTime().seconds <= fps.seconds(33) {
            guard Date() < playingDeadline else { throw RenderError.invalid("The installed timeline did not advance into playback.") }
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        guard errorMessage == nil else { throw RenderError.invalid(errorMessage!) }
        print("RENDER_EDIT_SMOKE_OK import split undo redo roll ripple range transform keyframe playback")
    }
}
