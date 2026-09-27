import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import RenderCore

/// Disposable, bounded derived data. Cache failures never prevent importing source media.
struct MediaCache {
    let folder: URL
    init(folder: URL? = nil) {
        self.folder = folder ?? FileManager.default.urls(for: .cachesDirectory,in: .userDomainMask)[0].appendingPathComponent("Render/Media",isDirectory: true)
    }
    func key(_ source: URL,operation: String) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        var data = try encoder.encode(SourceFingerprint(url: source))
        data.append(Data(operation.utf8))
        return SHA256.hash(data: data).map { String(format: "%02x",$0) }.joined()
    }
    func read(_ key: String) -> Data? {
        let url = folder.appendingPathComponent(key)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber, size.intValue <= 8 * 1024 * 1024,
              let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()],ofItemAtPath: url.path)
        return data
    }
    func write(_ data: Data,key: String) {
        guard data.count <= 8 * 1024 * 1024 else { return }
        do {
            try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
            try data.write(to: folder.appendingPathComponent(key),options: .atomic)
            trim()
        } catch { /* Derived data is optional; originals remain authoritative. */ }
    }
    func image(_ key: String) -> CGImage? {
        guard let data = read(key), let source = CGImageSourceCreateWithData(data as CFData,nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways: true,kCGImageSourceThumbnailMaxPixelSize: 320] as CFDictionary)
    }
    func write(_ image: CGImage,key: String) {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data,UTType.png.identifier as CFString,1,nil) else { return }
        CGImageDestinationAddImage(destination,image,nil)
        if CGImageDestinationFinalize(destination) { write(data as Data,key: key) }
    }
    private func trim() {
        let keys: Set<URLResourceKey> = [.fileSizeKey,.contentModificationDateKey,.isRegularFileKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: folder,includingPropertiesForKeys: Array(keys),options: .skipsHiddenFiles) else { return }
        var entries: [(URL,Int,Date)] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            entries.append((url,values.fileSize ?? 0,values.contentModificationDate ?? .distantPast))
        }
        var total = entries.reduce(0) { $0 + $1.1 }, count = entries.count
        for entry in entries.sorted(by: { $0.2 < $1.2 }) {
            if total <= 256 * 1024 * 1024 && count <= 4096 { break }
            try? FileManager.default.removeItem(at: entry.0); total -= entry.1; count -= 1
        }
    }
}
