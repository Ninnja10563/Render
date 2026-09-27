import Foundation

public struct CaptionCue: Equatable, Sendable {
    public var start: Int64
    public var end: Int64
    public var text: String
    public init(start: Int64,end: Int64,text: String) { self.start = start; self.end = end; self.text = text }
}
public enum SRTCodec {
    public static func decode(_ input: String,rate: FrameRate) throws -> [CaptionCue] {
        guard input.utf8.count <= 8 * 1024 * 1024, rate.value.isFinite, (1...120).contains(rate.value) else { throw RenderError.invalid("Invalid caption file or frame rate.") }
        let normalized = input.replacingOccurrences(of: "\u{FEFF}",with: "").replacingOccurrences(of: "\r\n",with: "\n").replacingOccurrences(of: "\r",with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var cues: [CaptionCue] = [], index = 0
        while index < lines.count {
            if lines[index].trimmingCharacters(in: .whitespaces).isEmpty { index += 1; continue }
            if !lines[index].contains("-->") {
                guard Int(lines[index].trimmingCharacters(in: .whitespaces)) != nil else { throw RenderError.invalid("Invalid caption number at line \(index + 1).") }
                index += 1
            }
            guard index < lines.count else { throw RenderError.invalid("Missing caption timing.") }
            let timing = lines[index].components(separatedBy: "-->")
            guard timing.count == 2 else { throw RenderError.invalid("Invalid caption timing at line \(index + 1).") }
            let startMS = try milliseconds(timing[0]), endMS = try milliseconds(timing[1])
            guard endMS > startMS else { throw RenderError.invalid("A caption must end after it starts.") }
            index += 1; var text: [String] = []
            while index < lines.count && !lines[index].trimmingCharacters(in: .whitespaces).isEmpty { text.append(lines[index]); index += 1 }
            guard !text.isEmpty else { throw RenderError.invalid("A caption has no text.") }
            let start = rate.frames(Double(startMS) / 1000), end = max(start + 1,rate.frames(Double(endMS) / 1000))
            guard start >= 0, end < 100_000_000 else { throw RenderError.invalid("Caption exceeds timeline bounds.") }
            let content = text.joined(separator: "\n").replacingOccurrences(of: "<[^>]+>",with: "",options: .regularExpression)
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, content.utf8.count <= 40_000 else { throw RenderError.invalid("Caption text is too long.") }
            cues.append(CaptionCue(start: start,end: end,text: content))
            guard cues.count <= 20_000 else { throw RenderError.invalid("Caption file has too many cues.") }
        }
        return cues.sorted { $0.start < $1.start }
    }
    public static func encode(_ cues: [CaptionCue],rate: FrameRate) throws -> String {
        guard rate.value.isFinite, (1...120).contains(rate.value) else { throw RenderError.invalid("Invalid caption frame rate.") }
        return try cues.sorted { $0.start < $1.start }.enumerated().map { index,cue in
            guard cue.start >= 0, cue.end > cue.start, cue.end < 100_000_000, cue.text.utf8.count <= 40_000, !cue.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw RenderError.invalid("Invalid caption cue.") }
            return "\(index + 1)\n\(timestamp(rate.seconds(cue.start))) --> \(timestamp(rate.seconds(cue.end)))\n\(cue.text)\n"
        }.joined(separator: "\n")
    }
    private static func milliseconds(_ raw: String) throws -> Int64 {
        let token = raw.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
        let parts = token.replacingOccurrences(of: ".",with: ",").split(whereSeparator: { $0 == ":" || $0 == "," })
        guard parts.count == 4, parts[3].count == 3,
              let h = Int64(parts[0]), let m = Int64(parts[1]), let s = Int64(parts[2]), let ms = Int64(parts[3]),
              (0...9999).contains(h), (0...59).contains(m), (0...59).contains(s), (0...999).contains(ms) else { throw RenderError.invalid("Invalid SRT timestamp: \(token)") }
        return ((h * 60 + m) * 60 + s) * 1000 + ms
    }
    private static func timestamp(_ seconds: Double) -> String {
        let ms = Int64((seconds * 1000).rounded())
        return String(format: "%02lld:%02lld:%02lld,%03lld",ms / 3_600_000,(ms / 60_000) % 60,(ms / 1000) % 60,ms % 1000)
    }
}
