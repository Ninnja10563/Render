import Foundation
import AVFoundation
import AppKit
import RenderCore

public actor MediaLibrary {
    private var thumbnails: [String: CGImage] = [:]
    private var waveforms: [String: [Float]] = [:]
    private let cache: MediaCache
    public init(cacheFolder: URL? = nil) { cache = MediaCache(folder: cacheFolder) }
    public func analyze(_ url: URL) async throws -> MediaAsset {
        guard FileManager.default.fileExists(atPath: url.path) else { throw RenderError.missingMedia(url.lastPathComponent) }
        let cacheKey = try cache.key(url,operation: "metadata-v1")
        if let data = cache.read(cacheKey), var cached = try? JSONDecoder().decode(MediaAsset.self,from: data), cached.duration.isFinite, cached.duration > 0 {
            cached.id = UUID(); cached.url = url; cached.variants = nil
            return cached
        }
        if ["png","jpg","jpeg","tif","tiff"].contains(url.pathExtension.lowercased()) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw RenderError.invalid("Cannot decode \(url.lastPathComponent).") }
            let result = MediaAsset(url: url, kind: .image, duration: 5, width: image.width, height: image.height, codec: url.pathExtension.uppercased())
            if let data = try? JSONEncoder().encode(result) { cache.write(data,key: cacheKey) }
            return result
        }
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw RenderError.invalid("Media has no playable duration: \(url.lastPathComponent).") }
        let videos = try await asset.loadTracks(withMediaType: .video)
        let audios = try await asset.loadTracks(withMediaType: .audio)
        guard !videos.isEmpty || !audios.isEmpty else { throw RenderError.invalid("Unsupported media: \(url.lastPathComponent).") }
        var channels = 0
        if let audio = audios.first, let format = try await audio.load(.formatDescriptions).first,
           let description = CMAudioFormatDescriptionGetStreamBasicDescription(format) { channels = Int(description.pointee.mChannelsPerFrame) }
        var result = MediaAsset(url: url, kind: videos.isEmpty ? .audio : .video, duration: duration, audioChannels: channels)
        if let video = videos.first {
            let size = try await video.load(.naturalSize)
            let transform = try await video.load(.preferredTransform)
            let display = CGRect(origin: .zero, size: size).applying(transform)
            result.width = Int(abs(display.width)); result.height = Int(abs(display.height))
            result.frameRate = Double(try await video.load(.nominalFrameRate))
            if let format = try await video.load(.formatDescriptions).first {
                let code = CMFormatDescriptionGetMediaSubType(format)
                result.codec = String(bytes: [UInt8((code >> 24) & 255), UInt8((code >> 16) & 255), UInt8((code >> 8) & 255), UInt8(code & 255)], encoding: .ascii) ?? "Video"
            }
        } else { result.codec = url.pathExtension.uppercased() }
        if let data = try? JSONEncoder().encode(result) { cache.write(data,key: cacheKey) }
        return result
    }
    public func thumbnail(_ asset: MediaAsset) async throws -> CGImage? {
        guard asset.kind != .audio else { return nil }
        let key = try cache.key(asset.url,operation: "thumbnail-v1")
        if let cached = thumbnails[key] { return cached }
        if let image = cache.image(key) { if thumbnails.count >= 200 { thumbnails.removeAll(keepingCapacity: true) }; thumbnails[key] = image; return image }
        let image: CGImage
        if asset.kind == .image {
            guard let source = CGImageSourceCreateWithURL(asset.url as CFURL, nil),
                  let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 320, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { throw RenderError.invalid("Could not create image thumbnail.") }
            image = decoded
        } else {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: asset.url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 320, height: 180)
            image = try await generator.image(at: CMTime(seconds: min(0.25,asset.duration / 2), preferredTimescale: 600)).image
        }
        if thumbnails.count >= 200 { thumbnails.removeAll(keepingCapacity: true) }
        thumbnails[key] = image; cache.write(image,key: key)
        return image
    }
    public func waveform(_ media: MediaAsset, bins: Int = 400) async throws -> [Float] {
        guard (1...100_000).contains(bins), media.duration.isFinite, media.duration > 0 else { throw RenderError.invalid("Invalid waveform dimensions.") }
        let key = try cache.key(media.url,operation: "waveform-v2-\(bins)-\(media.duration)")
        if let cached = waveforms[key] { return cached }
        if let data = cache.read(key), let values = try? JSONDecoder().decode([Float].self,from: data), values.count == bins, values.allSatisfy({ $0.isFinite && (0...1).contains($0) }) {
            if waveforms.count >= 200 { waveforms.removeAll(keepingCapacity: true) }; waveforms[key] = values; return values
        }
        let asset = AVURLAsset(url: media.url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return [] }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMIsFloatKey: true, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsNonInterleaved: false])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? RenderError.invalid("Cannot read audio samples.") }
        var peaks = [Float](repeating: 0, count: bins)
        var buffersRead = 0
        while let sample = output.copyNextSampleBuffer() {
            buffersRead += 1
            if buffersRead % 16 == 0 { await Task.yield() }
            if Task.isCancelled { reader.cancelReading(); throw CancellationError() }
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let count = CMBlockBufferGetDataLength(block) / MemoryLayout<Float>.size
            var samples = [Float](repeating: 0, count: count)
            let status = samples.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: $0.count, destination: $0.baseAddress!) }
            guard status == kCMBlockBufferNoErr else { continue }
            let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            let span = CMSampleBufferGetDuration(sample).seconds
            for i in samples.indices {
                let seconds = time + (span.isFinite ? span : 0) * Double(i) / Double(max(1,count))
                let bin = min(bins - 1, max(0, Int(seconds / media.duration * Double(bins))))
                if samples[i].isFinite { peaks[bin] = max(peaks[bin], min(1, abs(samples[i]))) }
            }
        }
        if reader.status == .failed { throw reader.error ?? RenderError.invalid("Audio waveform decoding failed.") }
        if waveforms.count >= 200 { waveforms.removeAll(keepingCapacity: true) }
        waveforms[key] = peaks
        if let data = try? JSONEncoder().encode(peaks) { cache.write(data,key: key) }
        return peaks
    }
    public func invalidate(_ url: URL) { thumbnails.removeAll(); waveforms.removeAll() }
}
