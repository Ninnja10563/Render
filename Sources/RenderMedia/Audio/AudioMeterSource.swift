import Foundation
import MediaToolbox
import RenderCore
import RenderAudioDSP

public struct AudioMeterReading: Sendable {
    public var start: Double
    public var end: Double
    public var peaks: [Float]
    public var rms: [Float]
}
/// Immutable owner of a tap and its lock-free measurement ring. The tap only observes audio.
public final class AudioMeterSource: @unchecked Sendable, Identifiable {
    public let id = UUID()
    public let name: String
    public let measuring: Bool
    public var processingFailed: Bool { RenderMeterProcessingFailed(handle) }
    let tap: MTAudioProcessingTap
    private let handle: RenderMeterRef
    // Populated during composition compilation, before this owner is published to playback/UI.
    private var segments: [(start: Double,end: Double,name: String)] = []
    func appendLabel(_ name: String,start: Double,end: Double) { segments.append((start,end,name)) }
    public func displayName(at seconds: Double) -> String {
        var low = 0, high = segments.count
        while low < high { let mid = (low + high) / 2; if segments[mid].start <= seconds { low = mid + 1 } else { high = mid } }
        if low > 0, seconds < segments[low - 1].end { return segments[low - 1].name }
        return name
    }
    init(name: String,measuring: Bool = true) throws {
        guard let handle = RenderMeterCreate(measuring) else { throw RenderError.invalid("Cannot allocate audio metering storage.") }
        guard let tap = RenderMeterCreateTap(handle) else { RenderMeterRelease(handle); throw RenderError.invalid("Cannot create an audio processing tap.") }
        self.handle = handle; self.tap = tap; self.name = name; self.measuring = measuring
    }
    func appendEffects(_ effects: [AudioEffect],start: Double,end: Double) throws {
        let active = effects.filter(\.enabled)
        let descriptors = active.map { effect -> RenderAudioEffectDescriptor in
            var descriptor = RenderAudioEffectDescriptor()
            switch effect.kind { case .equalizer: descriptor.kind = 0; case .compressor: descriptor.kind = 1; case .limiter: descriptor.kind = 2; case .noiseGate: descriptor.kind = 3 }
            let values = effect.kind.parameters.map { effect.value($0.key) }
            withUnsafeMutableBytes(of: &descriptor.values) { buffer in
                let numbers = buffer.bindMemory(to: Double.self)
                for (index,value) in values.enumerated() { numbers[index] = value }
            }
            return descriptor
        }
        guard descriptors.withUnsafeBufferPointer({ RenderMeterAppendEffects(handle,start,end,$0.baseAddress,$0.count) }) else { throw RenderError.invalid("Cannot compile audio processors.") }
    }
    func appendVolumeRamp(from: Float,to: Float,start: Double,end: Double) throws {
        guard RenderMeterAppendRamp(handle,start,end,from,to) else { throw RenderError.invalid("Cannot compile audio meter automation.") }
    }
    deinit { RenderMeterRelease(handle) }
    public func read(at seconds: Double) -> AudioMeterReading? {
        var value = RenderMeterRead(handle,seconds)
        guard value.valid else { return nil }
        let count = Int(value.channels)
        let peaks = withUnsafeBytes(of: &value.peak) { Array($0.bindMemory(to: Float.self).prefix(count)) }
        let rms = withUnsafeBytes(of: &value.rms) { Array($0.bindMemory(to: Float.self).prefix(count)) }
        return AudioMeterReading(start: value.start,end: value.end,peaks: peaks,rms: rms)
    }
}
