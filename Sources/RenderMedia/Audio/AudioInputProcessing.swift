import AVFoundation
import RenderCore

/// One optional tap per reusable composition input. Clip-local nonlinear processors run
/// before volume/mixing; compound bus processors are deliberately not approximated per leaf.
final class AudioInputProcessing {
    let metering: Bool
    private var byTrack: [CMPersistentTrackID: AudioMeterSource] = [:]
    private(set) var inputs: [AudioMeterSource] = []
    var meters: [AudioMeterSource] { inputs.filter(\.measuring) }
    init(metering: Bool) { self.metering = metering }
    func attach(clip: TimelineClip,name: String,target: AVMutableCompositionTrack,mix: AVMutableAudioMixInputParameters,start: Double,end: Double) throws -> AudioMeterSource? {
        let effects = (clip.properties.audioEffects ?? []).filter(\.enabled)
        guard metering || !effects.isEmpty || byTrack[target.trackID] != nil else { return nil }
        let input: AudioMeterSource
        if let existing = byTrack[target.trackID] { input = existing }
        else {
            input = try AudioMeterSource(name: name,measuring: metering)
            mix.audioTapProcessor = input.tap; byTrack[target.trackID] = input; inputs.append(input)
        }
        input.appendLabel(name,start: start,end: end)
        try input.appendEffects(effects,start: start,end: end)
        return input
    }
}
