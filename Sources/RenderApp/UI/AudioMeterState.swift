import SwiftUI
import RenderMedia

struct AudioMeterDisplay: Identifiable {
    let id: UUID
    var name: String
    var peaks: [Float]
    var rms: [Float]
}
@MainActor
final class AudioMeterState: ObservableObject {
    @Published private(set) var inputs: [AudioMeterDisplay] = []
    private var sources: [AudioMeterSource] = []
    private var lastUpdate: TimeInterval = 0
    func install(_ sources: [AudioMeterSource]) {
        self.sources = sources; lastUpdate = 0
        inputs = sources.map { AudioMeterDisplay(id: $0.id,name: $0.name,peaks: [],rms: []) }
    }
    func clearLevels() {
        guard inputs.contains(where: { $0.peaks.contains(where: { $0 != 0 }) || $0.rms.contains(where: { $0 != 0 }) }) else { return }
        var cleared = inputs
        for index in cleared.indices { cleared[index].peaks = cleared[index].peaks.map { _ in 0 }; cleared[index].rms = cleared[index].rms.map { _ in 0 } }
        inputs = cleared
    }
    func update(seconds: Double,playing: Bool) {
        let now = Date.timeIntervalSinceReferenceDate
        guard now - lastUpdate >= 1 / 30.0 else { return }
        let elapsed = min(1,max(0,now - lastUpdate)); lastUpdate = now
        guard playing else {
            if inputs.contains(where: { $0.peaks.contains(where: { $0 > 0 }) }) { clearLevels() }
            return
        }
        let decay = Float(pow(10,-elapsed)) // 20 dB per second peak falloff; samples are measured, not synthesized.
        var updated = inputs
        for index in sources.indices {
            updated[index].name = sources[index].displayName(at: seconds)
            if let reading = sources[index].read(at: seconds) {
                let previous = updated[index].peaks
                updated[index].peaks = reading.peaks.enumerated().map { channel,peak in max(peak,channel < previous.count ? previous[channel] * decay : 0) }
                updated[index].rms = reading.rms
            } else {
                updated[index].peaks = inputs[index].peaks.map { $0 * decay }
                updated[index].rms = inputs[index].rms.map { _ in 0 }
            }
        }
        inputs = updated
    }
}

struct AudioInputMetersView: View {
    @ObservedObject var meters: AudioMeterState
    var body: some View {
        if !meters.inputs.isEmpty {
            VStack(alignment: .leading,spacing: 10) {
                Text("INPUT LEVELS · dBFS").font(.system(size: 9,weight: .semibold)).foregroundStyle(.secondary)
                    .help("Decoded input levels after clip and ancestor volume/fades. These are separate composition inputs, not the summed master output.")
                ForEach(meters.inputs) { input in
                    VStack(alignment: .leading,spacing: 4) {
                        Text(input.name).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                        if input.peaks.isEmpty { Text("Waiting for playback").font(.system(size: 9)).foregroundStyle(.tertiary) }
                        ForEach(input.peaks.indices,id: \.self) { channel in
                            meter(peak: input.peaks[channel],rms: channel < input.rms.count ? input.rms[channel] : 0,channel: channel)
                        }
                    }
                }
            }
        }
    }
    private func position(_ value: Float) -> CGFloat { CGFloat(max(0,min(1,(20 * log10(max(0.000001,value)) + 60) / 60))) }
    private func meter(peak: Float,rms: Float,channel: Int) -> some View {
        HStack(spacing: 5) {
            Text("\(channel + 1)").foregroundStyle(.tertiary).frame(width: 9)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.primary.opacity(0.07))
                    Rectangle().fill(peak >= 1 ? Color.red : peak >= 0.707 ? .orange : .green).frame(width: geometry.size.width * position(rms))
                    Rectangle().fill(peak >= 1 ? Color.red : Color.primary.opacity(0.8)).frame(width: 1).offset(x: max(0,geometry.size.width * position(peak) - 1))
                }
            }.frame(height: 6)
            Text(peak > 0.000001 ? String(format: "%.1f",20 * log10(peak)) : "−∞").monospacedDigit().frame(width: 31,alignment: .trailing)
        }.font(.system(size: 9))
    }
}
