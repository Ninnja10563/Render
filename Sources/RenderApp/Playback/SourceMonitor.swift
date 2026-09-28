import AVFoundation
import SwiftUI
import ImageIO
import RenderCore

@MainActor
final class SourceMonitor: ObservableObject {
    let player = AVPlayer()
    @Published private(set) var asset: MediaAsset?
    @Published private(set) var frame: Int64 = 0
    @Published private(set) var playing = false
    @Published private(set) var error: String?
    @Published private(set) var still: CGImage?
    @Published private(set) var ready = false
    @Published private(set) var reversePreview = false
    private(set) var rate = FrameRate()
    private var observer: Any?
    private var observation: NSKeyValueObservation?
    private var imageTask: Task<Void,Never>?
    private var reverseTask: Task<Void,Never>?
    var totalFrames: Int64 { max(1,Int64(floor((asset?.duration ?? 0) * rate.value + 0.0000001))) }
    var range: SourceSelection { asset?.selection ?? SourceSelection(start: 0,end: rate.seconds(totalFrames)) }
    init() {
        player.actionAtItemEnd = .pause
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1,timescale: 30),queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self,time.seconds.isFinite else { return }
                if self.player.rate != 0 { self.frame = min(self.totalFrames - 1,max(0,self.rate.frames(time.seconds))) }
                self.playing = self.player.rate != 0 || self.reversePreview
            }
        }
    }
    deinit { if let observer { player.removeTimeObserver(observer) }; imageTask?.cancel(); reverseTask?.cancel() }
    func configure(_ media: MediaAsset,rate: FrameRate) {
        let unchanged = asset?.hasSamePlaybackSource(as: media) == true && self.rate == rate
        asset = media; self.rate = rate
        if unchanged { updateBounds(); return }
        pause(); imageTask?.cancel(); observation = nil; still = nil; error = nil; frame = 0; ready = false
        guard FileManager.default.fileExists(atPath: media.url.path) else { error = "Missing source media. Use Relink Media to locate it."; player.replaceCurrentItem(with: nil); return }
        if media.kind == .image {
            player.replaceCurrentItem(with: nil)
            imageTask = Task { [weak self] in
                let image = await Task.detached(priority: .userInitiated) {
                    guard let source = CGImageSourceCreateWithURL(media.url as CFURL,nil) else { return nil as CGImage? }
                    return CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:2048,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary)
                }.value
                guard !Task.isCancelled,let self,self.asset?.id == media.id else { return }
                self.still = image; self.ready = image != nil
                if image == nil { self.error = "Cannot decode the source image." }
            }
        } else {
            let item = AVPlayerItem(url: media.url)
            observation = item.observe(\.status,options: [.initial,.new]) { [weak self] item,_ in
                Task { @MainActor in
                    guard let self,self.player.currentItem === item else { return }
                    self.ready = item.status == .readyToPlay
                    if item.status == .failed { self.error = item.error?.localizedDescription ?? "Cannot decode this source." }
                }
            }
            player.replaceCurrentItem(with: item); updateBounds()
        }
    }
    private func updateBounds() {
        player.currentItem?.forwardPlaybackEndTime = CMTime(seconds: range.end,preferredTimescale: 600000)
        player.currentItem?.reversePlaybackEndTime = CMTime(seconds: range.start,preferredTimescale: 600000)
    }
    func clear() { pause(); imageTask?.cancel(); observation = nil; player.replaceCurrentItem(with: nil); asset = nil; still = nil; ready = false; error = nil; frame = 0 }
    func pause() { reverseTask?.cancel(); reverseTask = nil; reversePreview = false; player.currentItem?.cancelPendingSeeks(); player.pause(); playing = false }
    func seek(_ frame: Int64) {
        pause(); self.frame = min(totalFrames - 1,max(0,frame))
        player.seek(to: CMTime(value: self.frame * Int64(rate.denominator),timescale: rate.numerator),toleranceBefore: .zero,toleranceAfter: .zero)
    }
    func togglePlayback() { if playing { pause() } else { shuttle(1) } }
    func shuttle(_ direction: Int) {
        guard ready,asset?.kind != .image else { return }
        let speed: Float = min(4,playing ? max(1,abs(player.rate)) * 2 : 1)
        pause()
        if direction > 0 {
            if rate.seconds(frame) < range.start || rate.seconds(frame + 1) >= range.end { seek(rate.frames(range.start)) }
            player.playImmediately(atRate: speed); playing = true
        } else if player.currentItem?.canPlayReverse == true {
            if rate.seconds(frame) <= range.start { seek(max(0,rate.frames(range.end) - 1)) }
            player.rate = -speed; playing = true
        } else {
            if rate.seconds(frame) <= range.start { seek(max(0,rate.frames(range.end) - 1)) }
            let lower = rate.frames(range.start),clock = ReversePreviewClock(origin: frame,frameRate: rate,speed: Double(speed))
            let started = ProcessInfo.processInfo.systemUptime
            reversePreview = true; playing = true
            reverseTask = Task { [weak self] in
                guard let self else { return }
                while !Task.isCancelled {
                    let target = max(lower,clock.frame(elapsed: ProcessInfo.processInfo.systemUptime - started))
                    if target != self.frame {
                        let ok = await self.player.seek(to: CMTime(value: target * Int64(rate.denominator),timescale: rate.numerator),toleranceBefore: .zero,toleranceAfter: .zero)
                        guard !Task.isCancelled else { return }
                        guard ok else { self.pause(); self.error = "Cannot decode the reverse source frame."; return }
                        self.frame = target
                    }
                    if target == lower { self.pause(); return }
                    do { try await Task.sleep(nanoseconds: 8_000_000) } catch { return }
                }
            }
        }
    }
}
