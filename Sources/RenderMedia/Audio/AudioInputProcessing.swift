import AVFoundation
import RenderCore

/// One optional tap per reusable composition input. Clip-local nonlinear processors run
/// before volume/mixing; compound bus processors are deliberately not approximated per leaf.
final class AudioInputProcessing {
    let metering: Bool
    private var byTrack: [CMPersistentTrackID: AudioMeterSource] = [:]
    private struct SourceTail {
        let asset: UUID?, sourceEnd: Double, end: Double, speed: Double, effects: [AudioEffect]
    }
    private var tails: [CMPersistentTrackID: SourceTail] = [:]
    private(set) var inputs: [AudioMeterSource] = []
    var meters: [AudioMeterSource] { inputs.filter(\.measuring) }
    init(metering: Bool) { self.metering = metering }
    func attach(clip: TimelineClip,name: String,target: AVMutableCompositionTrack,mix: AVMutableAudioMixInputParameters,start: Double,end: Double,sourceStart: Double,sourceEnd: Double,speed: Double) throws -> AudioMeterSource? {
        let effects = (clip.properties.audioEffects ?? []).filter(\.enabled)
        guard metering || !effects.isEmpty || byTrack[target.trackID] != nil else { return nil }
        let input: AudioMeterSource
        if let existing = byTrack[target.trackID] { input = existing }
        else {
            input = try AudioMeterSource(name: name,measuring: metering)
            mix.audioTapProcessor = input.tap; byTrack[target.trackID] = input; inputs.append(input)
        }
        input.appendLabel(name,start: start,end: end)
        let previous = tails[target.trackID]
        let continuous = previous.map { $0.asset == clip.assetID && $0.effects == effects && abs($0.end - start) < 1e-7 && abs($0.sourceEnd - sourceStart) < 0.00001 && abs($0.speed - speed) < 1e-10 } ?? false
        try input.appendEffects(effects,start: start,end: end,continuous: continuous)
        tails[target.trackID] = SourceTail(asset: clip.assetID,sourceEnd: sourceEnd,end: end,speed: speed,effects: effects)
        return input
    }
}
