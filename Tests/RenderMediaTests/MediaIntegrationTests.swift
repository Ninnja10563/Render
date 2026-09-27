import XCTest
import AVFoundation
import AppKit
@testable import RenderMedia
import RenderCore

final class MediaIntegrationTests: XCTestCase {
    func makeImage(in folder: URL, name: String = "red.png", color: NSColor = .red) throws -> URL {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,pixelsWide: 320,pixelsHigh: 180,bitsPerSample: 8,samplesPerPixel: 4,hasAlpha: true,isPlanar: false,colorSpaceName: .deviceRGB,bytesPerRow: 0,bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        color.setFill(); NSBezierPath(rect: NSRect(x: 0,y: 0,width: 320,height: 180)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let url = folder.appendingPathComponent(name)
        try bitmap.representation(using: .png,properties: [:])!.write(to: url)
        return url
    }
    @MainActor
    func testStillImageCompositionExportAndReimport() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try makeImage(in: folder)
        let library = MediaLibrary()
        let media = try await library.analyze(url)
        XCTAssertEqual(media.kind,.image); XCTAssertEqual(media.width,320)
        let thumbnail = try await library.thumbnail(media)
        XCTAssertNotNil(thumbnail)
        var project = RenderProject(); project.settings.width = 320; project.settings.height = 180
        project.assets = [media]
        var clip = TimelineClip(assetID: media.id,name: media.name,start: 15,duration: 30)
        clip.effects = [Effect(kind: .saturation)]
        project.tracks[0].clips = [clip]
        var configuration = ExportConfiguration(); configuration.width = 320; configuration.height = 180
        let output = folder.appendingPathComponent("out.mp4")
        let service = ExportService()
        try await service.export(project: project,configuration: configuration,to: output)
        XCTAssertEqual(service.progress,1)
        let result = try await library.analyze(output)
        XCTAssertEqual(result.kind,.video)
        XCTAssertEqual(result.width,320); XCTAssertEqual(result.height,180)
        XCTAssertEqual(result.duration,1.5,accuracy: 0.08)
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: output))
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        let black = try await generator.image(at: CMTime(seconds: 0.1,preferredTimescale: 600)).image
        let red = try await generator.image(at: CMTime(seconds: 0.8,preferredTimescale: 600)).image
        let blackPixel = pixel(black); let redPixel = pixel(red)
        XCTAssertLessThan(blackPixel[0],20)
        XCTAssertGreaterThan(redPixel[0],180); XCTAssertLessThan(redPixel[1],40)
        // Round-trip a real encoded video through source-track decoding, speed and the compositor.
        var videoProject = RenderProject(); videoProject.settings = project.settings; videoProject.assets = [result]
        var videoClip = TimelineClip(assetID: result.id,name: "Encoded",start: 0,duration: 15)
        videoClip.sourceIn = 0.5; videoClip.speed = 2
        videoProject.tracks[0].clips = [videoClip]
        let roundtrip = folder.appendingPathComponent("roundtrip.mp4")
        try await service.export(project: videoProject,configuration: configuration,to: roundtrip)
        let roundtripMedia = try await library.analyze(roundtrip)
        XCTAssertEqual(roundtripMedia.duration,0.5,accuracy: 0.08)
        do { try await service.export(project: project,configuration: configuration,to: output); XCTFail("Existing output overwritten") } catch {}
    }
    @MainActor
    func testLayerOrderOpacityAndEffectParity() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = MediaLibrary()
        let red = try await library.analyze(makeImage(in: folder))
        let blue = try await library.analyze(makeImage(in: folder,name: "blue.png",color: .blue))
        var project = RenderProject(); project.settings.width = 320; project.settings.height = 180
        project.assets = [red,blue]
        var top = TimelineClip(assetID: red.id,name: "Red",start: 0,duration: 15)
        top.properties.opacity = 0.5
        project.tracks[0].clips = [top]
        var lower = TimelineTrack(name: "Lower",kind: .video)
        lower.clips = [TimelineClip(assetID: blue.id,name: "Blue",start: 0,duration: 15)]
        project.tracks.insert(lower,at: 1)
        let prepared = try await CompositionBuilder().build(project)
        let generator = AVAssetImageGenerator(asset: prepared.composition)
        generator.videoComposition = prepared.videoComposition
        let preview = try await generator.image(at: CMTime(seconds: 0.2,preferredTimescale: 600)).image
        var config = ExportConfiguration(); config.width = 320; config.height = 180
        let output = folder.appendingPathComponent("mix.mp4")
        try await ExportService().export(project: project,configuration: config,to: output)
        let encoded = try await AVAssetImageGenerator(asset: AVURLAsset(url: output)).image(at: CMTime(seconds: 0.2,preferredTimescale: 600)).image
        let a = pixel(preview), b = pixel(encoded)
        XCTAssertGreaterThan(a[0],80); XCTAssertGreaterThan(a[2],80); XCTAssertLessThan(a[1],40)
        for i in 0..<3 { XCTAssertEqual(Double(a[i]),Double(b[i]),accuracy: 15) }
    }
    @MainActor
    func testAnimatedEffectPreviewMatchesExportAtMultipleFrames() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let media = try await MediaLibrary().analyze(makeImage(in: folder,color: NSColor(white: 0.25,alpha: 1)))
        var project = RenderProject(); project.settings.width = 320; project.settings.height = 180; project.assets = [media]
        var clip = TimelineClip(assetID: media.id,name: "Animated exposure",start: 0,duration: 30)
        var effect = Effect(kind: .exposure)
        effect.animation = AnimationCurve(keys: [Keyframe(frame: 0,value: 0,interpolation: .easeInOut),Keyframe(frame: 29,value: 2)])
        clip.effects = [effect]; project.tracks[0].clips = [clip]
        let prepared = try await CompositionBuilder().build(project)
        let preview = AVAssetImageGenerator(asset: prepared.composition); preview.videoComposition = prepared.videoComposition
        preview.requestedTimeToleranceBefore = .zero; preview.requestedTimeToleranceAfter = .zero
        var config = ExportConfiguration(); config.width = 320; config.height = 180
        let output = folder.appendingPathComponent("animation.mp4")
        try await ExportService().export(project: project,configuration: config,to: output)
        let exported = AVAssetImageGenerator(asset: AVURLAsset(url: output))
        exported.requestedTimeToleranceBefore = .zero; exported.requestedTimeToleranceAfter = .zero
        var samples: [UInt8] = []
        for frame: Int64 in [0,15,29] {
            let time = CMTime(value: frame,timescale: 30)
            let a = pixel(try await preview.image(at: time).image)
            let b = pixel(try await exported.image(at: time).image)
            for channel in 0..<3 { XCTAssertEqual(Double(a[channel]),Double(b[channel]),accuracy: 15) }
            samples.append(a[0])
        }
        XCTAssertGreaterThan(samples[1],samples[0] + 10)
        XCTAssertGreaterThan(samples[2],samples[1] + 10)
    }
    func testMissingAndCorruptMediaFailGracefully() async throws {
        let library = MediaLibrary()
        do { _ = try await library.analyze(URL(fileURLWithPath: "/nonexistent/Render-test.mov")); XCTFail("Missing file accepted") } catch {}
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not a movie".utf8).write(to: url)
        do { _ = try await library.analyze(url); XCTFail("Corrupt media accepted") } catch {}
    }
    private func pixel(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0,count: 4)
        bytes.withUnsafeMutableBytes { ptr in
            let context = CGContext(data: ptr.baseAddress,width: 1,height: 1,bitsPerComponent: 8,bytesPerRow: 4,space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image,in: CGRect(x: 0,y: 0,width: 1,height: 1))
        }
        return bytes
    }
}

extension MediaIntegrationTests {
    @MainActor
    func testAudioOnlyTimelineWaveformMuteAndExport() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("tone.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000,channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format,frameCapacity: 48000)!
        buffer.frameLength = 48000
        for index in 0..<48000 { buffer.floatChannelData![0][index] = Float(sin(Double(index) * 440 * 2 * .pi / 48000)) * 0.4 }
        do { let file = try AVAudioFile(forWriting: url,settings: format.settings); try file.write(from: buffer) }
        let library = MediaLibrary()
        let media = try await library.analyze(url)
        XCTAssertEqual(media.kind,.audio); XCTAssertEqual(media.audioChannels,1)
        let peaks = try await library.waveform(media)
        XCTAssertEqual(peaks.count,400); XCTAssertGreaterThan(peaks.max() ?? 0,0.3)
        var project = RenderProject(); project.settings.width = 320; project.settings.height = 180; project.assets = [media]
        var clip = TimelineClip(assetID: media.id,name: "Tone",start: 0,duration: 30)
        clip.properties.volume = 0.5
        project.tracks[1].clips = [clip]
        var config = ExportConfiguration(); config.width = 320; config.height = 180
        let output = folder.appendingPathComponent("audio.mp4")
        try await ExportService().export(project: project,configuration: config,to: output)
        let result = try await library.analyze(output)
        XCTAssertGreaterThan(result.audioChannels,0)
        let exportedPeaks = try await library.waveform(result)
        XCTAssertEqual(Double(exportedPeaks.max() ?? 0),0.2,accuracy: 0.04)
        // Repeated video+audio edits must reuse timeline tracks, not allocate one decoder track per clip.
        var sequence = RenderProject(); sequence.settings = project.settings; sequence.assets = [result]
        sequence.tracks[0].clips = Array((0..<60).map { index in
            var clip = TimelineClip(assetID: result.id,name: "Edit \(index)",start: Int64(index * 3),duration: 3)
            clip.speed = index % 2 == 0 ? 2 : 0.5
            clip.sourceIn = 0.1
            return clip
        }.reversed())
        let built = try await CompositionBuilder().build(sequence)
        let videoTracks = built.composition.tracks.filter { $0.mediaType == .video }
        let audioTracks = built.composition.tracks.filter { $0.mediaType == .audio }
        XCTAssertEqual(videoTracks.count,2) // One sequence track plus the gap/still clock.
        XCTAssertEqual(audioTracks.count,1)
        XCTAssertEqual(built.videoComposition.instructions.count,60)
        XCTAssertEqual(built.composition.duration.seconds,6,accuracy: 0.01)
        let sequenceURL = folder.appendingPathComponent("sixty-edits.mp4")
        try await ExportService().export(project: sequence,configuration: config,to: sequenceURL)
        let sequenceMedia = try await library.analyze(sequenceURL)
        XCTAssertEqual(sequenceMedia.duration,6,accuracy: 0.08)
        XCTAssertGreaterThan(sequenceMedia.audioChannels,0)
        project.tracks[1].muted = true
        let muted = try await CompositionBuilder().build(project)
        XCTAssertTrue(muted.audioMix.inputParameters.isEmpty)
    }
}

extension MediaIntegrationTests {
    @MainActor
    func testKeyedAndMaskedCompositionPreviewExportParity() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = MediaLibrary()
        let green = try await library.analyze(makeImage(in: folder,name: "green.png",color: .green))
        let blue = try await library.analyze(makeImage(in: folder,name: "blue.png",color: .blue))
        var project = RenderProject(); project.settings.width = 320; project.settings.height = 180; project.assets = [green,blue]
        var top = TimelineClip(assetID: green.id,name: "Screen",start: 0,duration: 6)
        var key = Effect(kind: .chromaKey); var mask = EffectMask()
        mask.shape = .rectangle; mask.width = 0.5; mask.height = 1; mask.x = 0.25; mask.feather = 0
        key.mask = mask; top.effects = [key]; project.tracks[0].clips = [top]
        var lower = TimelineTrack(name: "Background",kind: .video)
        lower.clips = [TimelineClip(assetID: blue.id,name: "Blue",start: 0,duration: 6)]
        project.tracks.insert(lower,at: 1)
        let prepared = try await CompositionBuilder().build(project)
        let generator = AVAssetImageGenerator(asset: prepared.composition); generator.videoComposition = prepared.videoComposition
        let preview = try await generator.image(at: CMTime(value: 1,timescale: 30)).image
        var config = ExportConfiguration(); config.width = 320; config.height = 180
        let output = folder.appendingPathComponent("keyed.mp4")
        try await ExportService().export(project: project,configuration: config,to: output)
        let encoded = try await AVAssetImageGenerator(asset: AVURLAsset(url: output)).image(at: CMTime(value: 1,timescale: 30)).image
        for x in [40,240] {
            let rect = CGRect(x: x,y: 60,width: 16,height: 16)
            let a = pixel(try XCTUnwrap(preview.cropping(to: rect)))
            let b = pixel(try XCTUnwrap(encoded.cropping(to: rect)))
            XCTAssertGreaterThan(a[x == 40 ? 2 : 1],220)
            XCTAssertLessThan(a[x == 40 ? 1 : 2],30)
            for channel in 0..<3 { XCTAssertEqual(Double(a[channel]),Double(b[channel]),accuracy: 15) }
        }
    }
}

extension MediaIntegrationTests {
    @MainActor
    func testGeneratedMediaPlaybackAndOriginalOnlyExport() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = MediaLibrary()
        let red = try await library.analyze(makeImage(in: folder))
        let blue = try await library.analyze(makeImage(in: folder,name: "blue.png",color: .blue))
        var config = ExportConfiguration(); config.width = 320; config.height = 180
        var sourceProject = RenderProject(); sourceProject.settings.width = 320; sourceProject.settings.height = 180
        sourceProject.assets = [red]
        sourceProject.tracks[0].clips = [TimelineClip(assetID: red.id,name: "Original",start: 0,duration: 6)]
        let originalURL = folder.appendingPathComponent("original.mov")
        config.codec = .proRes
        try await ExportService().export(project: sourceProject,configuration: config,to: originalURL)
        var original = try await library.analyze(originalURL)
        let generator = MediaTranscoder()
        let proxy = try await generator.generate(original,mode: .proxy,in: folder)
        let optimized = try await generator.generate(original,mode: .optimized,in: folder)
        let proxyMedia = try await library.analyze(proxy.url)
        XCTAssertLessThanOrEqual(proxyMedia.width,1280)
        XCTAssertEqual(proxyMedia.duration,original.duration,accuracy: 0.04)
        XCTAssertTrue(FileManager.default.fileExists(atPath: optimized.url.path))
        original.variants = [proxy,optimized]
        var project = RenderProject(); project.settings = sourceProject.settings; project.assets = [original]
        project.tracks[0].clips = [TimelineClip(assetID: original.id,name: "With variants",start: 0,duration: 6)]
        for mode in [PlaybackMediaMode.proxy,.optimized] {
            let built = try await CompositionBuilder().build(project,mode: mode)
            XCTAssertTrue(built.originalFallbacks.isEmpty)
        }
        // Deliberately substitute a blue proxy to prove export ignores playback representations.
        sourceProject.assets = [blue]; sourceProject.tracks[0].clips[0].assetID = blue.id
        let blueURL = folder.appendingPathComponent("blue.mov")
        try await ExportService().export(project: sourceProject,configuration: config,to: blueURL)
        project.assets[0].variants = [MediaVariant(mode: .proxy,url: blueURL,source: try SourceFingerprint(url: originalURL))]
        let built = try await CompositionBuilder().build(project,mode: .proxy)
        let preview = AVAssetImageGenerator(asset: built.composition); preview.videoComposition = built.videoComposition
        let proxyPixel = pixel(try await preview.image(at: CMTime(value: 1,timescale: 30)).image)
        XCTAssertGreaterThan(proxyPixel[2],200); XCTAssertLessThan(proxyPixel[0],40)
        let final = folder.appendingPathComponent("final.mov")
        try await ExportService().export(project: project,configuration: config,to: final)
        let outputPixel = pixel(try await AVAssetImageGenerator(asset: AVURLAsset(url: final)).image(at: CMTime(value: 1,timescale: 30)).image)
        XCTAssertGreaterThan(outputPixel[0],200); XCTAssertLessThan(outputPixel[2],40)
        // Corrupt cached files must fall back instead of breaking a valid original timeline.
        try Data("broken proxy".utf8).write(to: blueURL)
        let fallback = try await CompositionBuilder().build(project,mode: .proxy)
        XCTAssertEqual(fallback.originalFallbacks,[original.name])
    }
    @MainActor
    func testQueuedTaskCancellationAndFailureRemainObservable() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let queue = BackgroundTasks(folder: folder)
        let cancelled = expectation(description: "Queued task cancelled")
        let unsupported = expectation(description: "Unsupported request failed")
        let video = MediaAsset(url: URL(fileURLWithPath: "/missing.mov"),kind: .video,duration: 1)
        let id = queue.enqueue(video,mode: .proxy) { result in
            if case .failure(let error) = result { XCTAssertTrue(error is CancellationError); cancelled.fulfill() }
        }
        queue.cancel(id)
        let image = MediaAsset(url: URL(fileURLWithPath: "/image.png"),kind: .image,duration: 5)
        queue.enqueue(image,mode: .proxy) { result in
            if case .failure = result { unsupported.fulfill() }
        }
        await fulfillment(of: [cancelled,unsupported],timeout: 5)
        XCTAssertEqual(queue.tasks.map(\.state),[.cancelled,.failed])
        XCTAssertEqual(queue.activeCount,0)
        queue.clearFinished(); XCTAssertTrue(queue.tasks.isEmpty)
    }
}

extension MediaIntegrationTests {
    @MainActor
    func testGeneratedTitleExportAndResolutionIndependentPosition() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var title = TitleContent(text: "Render"); title.fontSize = 30; title.background = RGBAColor(1,0,0)
        title.padding = 5; title.shadow.alpha = 0
        var project = RenderProject(); project.settings.width = 640; project.settings.height = 360
        project = try TimelineCommand.addTitle(title,at: 0,duration: 6).applying(to: project)
        project.tracks[0].clips[0].properties.x = 120
        var config = ExportConfiguration(); config.width = 320; config.height = 180
        let output = folder.appendingPathComponent("title.mp4")
        try await ExportService().export(project: project,configuration: config,to: output)
        let encoded = try await AVAssetImageGenerator(asset: AVURLAsset(url: output)).image(at: CMTime(value: 1,timescale: 30)).image
        // The title center moves 60 output pixels, preserving the 120-pixel sequence offset.
        let center = pixel(try XCTUnwrap(encoded.cropping(to: CGRect(x: 210,y: 90,width: 8,height: 8))))
        let wrongPosition = pixel(try XCTUnwrap(encoded.cropping(to: CGRect(x: 280,y: 90,width: 8,height: 8))))
        XCTAssertGreaterThan(center[0],180); XCTAssertLessThan(wrongPosition[0],30)
        let built = try await CompositionBuilder().build(project,outputSize: CGSize(width: 320,height: 180))
        let generator = AVAssetImageGenerator(asset: built.composition); generator.videoComposition = built.videoComposition
        let preview = try await generator.image(at: CMTime(value: 1,timescale: 30)).image
        let a = pixel(try XCTUnwrap(preview.cropping(to: CGRect(x: 210,y: 90,width: 8,height: 8))))
        for channel in 0..<3 { XCTAssertEqual(Double(a[channel]),Double(center[channel]),accuracy: 15) }
    }
}
