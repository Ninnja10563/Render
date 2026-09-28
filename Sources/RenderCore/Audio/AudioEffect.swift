import Foundation

public struct AudioEffectParameter: Sendable {
    public let key: String
    public let label: String
    public let range: ClosedRange<Double>
    public let defaultValue: Double
    public init(_ key: String,_ label: String,_ range: ClosedRange<Double>,_ value: Double) {
        self.key = key; self.label = label; self.range = range; defaultValue = value
    }
}
public enum AudioEffectKind: String, Codable, CaseIterable, Sendable {
    case equalizer, compressor, limiter, noiseGate
    public var label: String { switch self { case .equalizer: return "Three-Band EQ"; case .compressor: return "Compressor"; case .limiter: return "Sample Peak Limiter"; case .noiseGate: return "Noise Gate" } }
    /// Stable order also defines the native DSP descriptor layout.
    public var parameters: [AudioEffectParameter] {
        switch self {
        case .equalizer: return [.init("lowGain","Low gain (dB)",-24...24,0),.init("midGain","Mid gain (dB)",-24...24,0),.init("highGain","High gain (dB)",-24...24,0),.init("lowFrequency","Low frequency (Hz)",20...2000,120),.init("midFrequency","Mid frequency (Hz)",40...16000,1000),.init("highFrequency","High frequency (Hz)",1000...20000,6000),.init("q","Mid Q",0.1...10,1)]
        case .compressor: return [.init("threshold","Threshold (dB)",-60...0,-24),.init("ratio","Ratio",1...20,4),.init("attack","Attack (ms)",0.1...200,10),.init("release","Release (ms)",5...2000,100),.init("knee","Knee (dB)",0...24,6),.init("makeup","Makeup (dB)",-12...24,0)]
        case .limiter: return [.init("ceiling","Ceiling (dB)",-24...0,-1),.init("release","Release (ms)",5...1000,50)]
        case .noiseGate: return [.init("threshold","Threshold (dB)",-80...0,-50),.init("reduction","Closed gain (dB)",-96...0,-60),.init("attack","Attack (ms)",0.1...100,5),.init("release","Release (ms)",5...2000,150)]
        }
    }
}
public struct AudioEffect: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var kind: AudioEffectKind
    public var enabled = true
    public var values: [String: Double] = [:]
    public init(kind: AudioEffectKind) { self.kind = kind }
    public func value(_ key: String) -> Double { values[key] ?? kind.parameters.first(where: { $0.key == key })?.defaultValue ?? 0 }
    public func validate() throws {
        let parameters = Dictionary(uniqueKeysWithValues: kind.parameters.map { ($0.key,$0) })
        guard values.allSatisfy({ key,value in value.isFinite && parameters[key]?.range.contains(value) == true }) else { throw RenderError.invalid("Invalid audio effect parameter.") }
    }
}
