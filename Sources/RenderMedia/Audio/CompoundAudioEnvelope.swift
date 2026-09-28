import AVFoundation
import RenderCore

struct CompoundAudioEnvelope {
    let clip: TimelineClip
    let rate: FrameRate
    let mapping: TimelineTimeMapping
    let incoming: TransitionWindow?
    let outgoing: TransitionWindow?
    private let volume: AnimationSampler
    init(clip: TimelineClip,rate: FrameRate,mapping: TimelineTimeMapping,incoming: TransitionWindow?,outgoing: TransitionWindow?) {
        self.clip = clip; self.rate = rate; self.mapping = mapping; self.incoming = incoming; self.outgoing = outgoing
        volume = AnimationSampler(clip.properties.animations["volume"] ?? AnimationCurve())
    }
    var isIdentity: Bool { clip.properties.volume == 1 && volume.keys.isEmpty && clip.properties.audioFades == nil && incoming == nil && outgoing == nil }
    func gain(at seconds: Double) -> Double {
        let frame = mapping.local(seconds) * rate.value
        let animation = frame - Double(clip.start) + Double(clip.animationOffset)
        return volume.value(at: animation,fallback: clip.properties.volume) * (clip.properties.audioFades?.gain(at: animation) ?? 1) *
            (incoming?.progress(at: frame) ?? 1) * (outgoing.map { 1 - $0.progress(at: frame) } ?? 1)
    }
    var boundaries: [Double] {
        var frames = volume.keys.map { $0.frame - clip.animationOffset + clip.start }
        if let fade = clip.properties.audioFades {
            frames += [fade.start,fade.start + fade.fadeIn,fade.end - fade.fadeOut,fade.end].map { $0 - clip.animationOffset + clip.start }
        }
        if let incoming { frames += [incoming.start,incoming.end] }
        if let outgoing { frames += [outgoing.start,outgoing.end] }
        return frames.map { mapping.global(rate.seconds($0)) }
    }
}

enum CompoundAudioMix {
    static let timescale: Int32 = 600000
    static func time(_ seconds: Double) -> CMTime { CMTime(seconds: seconds,preferredTimescale: timescale) }
    static func apply(_ envelopes: [CompoundAudioEnvelope],window: RenderTimeWindow,to mix: AVMutableAudioMixInputParameters) {
        let start = time(window.start).value, end = time(window.end).value
        guard end > start else { return }
        let boundaries = Set([start,end] + envelopes.flatMap(\.boundaries).map { time($0).value }.filter { $0 > start && $0 < end }).sorted()
        func gain(_ ticks: Double) -> Float {
            let seconds = ticks / Double(timescale)
            return Float(envelopes.reduce(1.0) { $0 * $1.gain(at: seconds) })
        }
        for (a,b) in zip(boundaries,boundaries.dropFirst()) {
            let left = Double(a), right = Double(b) - 0.0001, middle = (left + right) / 2
            let varying = envelopes.contains { envelope in
                let x = envelope.gain(at: left / Double(timescale)), y = envelope.gain(at: middle / Double(timescale)), z = envelope.gain(at: right / Double(timescale))
                return abs(x - y) > 1e-9 || abs(y - z) > 1e-9
            }
            let parts = varying ? min(Int64(64),b - a) : 1
            for index in 0..<parts {
                let lo = a + (b - a) * index / parts, hi = a + (b - a) * (index + 1) / parts
                // Left limit at a segment end preserves Hold keyframe jumps.
                let to = gain(Double(hi) - (hi == b ? 0.0001 : 0))
                mix.setVolumeRamp(fromStartVolume: gain(Double(lo)),toEndVolume: to,timeRange: CMTimeRange(start: CMTime(value: lo,timescale: timescale),duration: CMTime(value: hi - lo,timescale: timescale)))
            }
        }
    }
}
