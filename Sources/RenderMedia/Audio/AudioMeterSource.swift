import Foundation
import MediaToolbox
import RenderCore
import RenderAudioDSP

public struct AudioMeterReading: Sendable {
    public var peaks: [Float]
    public var rms: [Float]
}
/// Immutable owner of a tap and its lock-free measurement ring. The tap only observes audio.
public final class AudioMeterSource: @unchecked Sendable, Identifiable {
    public let id = UUID()
    public let name: String
    let tap: MTAudioProcessingTap
    private let handle: RenderMeterRef
    init(name: String) throws {
        guard let handle = RenderMeterCreate() else { throw RenderError.invalid("Cannot allocate audio metering storage.") }
        guard let tap = RenderMeterCreateTap(handle) else { RenderMeterRelease(handle); throw RenderError.invalid("Cannot create an audio processing tap.") }
        self.handle = handle; self.tap = tap; self.name = name
    }
    deinit { RenderMeterRelease(handle) }
    public func read(at seconds: Double) -> AudioMeterReading? {
        var value = RenderMeterRead(handle,seconds)
        guard value.valid else { return nil }
        let count = Int(value.channels)
        let peaks = withUnsafeBytes(of: &value.peak) { Array($0.bindMemory(to: Float.self).prefix(count)) }
        let rms = withUnsafeBytes(of: &value.rms) { Array($0.bindMemory(to: Float.self).prefix(count)) }
        return AudioMeterReading(peaks: peaks,rms: rms)
    }
}
