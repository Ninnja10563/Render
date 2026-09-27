import Foundation

public actor ProjectStore {
    public init() {}
    public func remove(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    public func load(_ url: URL) throws -> RenderProject {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= 128 * 1024 * 1024 else { throw RenderError.invalid("Project exceeds the supported 128 MB document size.") }
        struct Header: Decodable { var schemaVersion: Int }
        let decoder = JSONDecoder()
        let header = try decoder.decode(Header.self, from: data)
        guard (1...RenderProject.currentSchema).contains(header.schemaVersion) else { throw RenderError.unsupportedVersion(header.schemaVersion) }
        var project = try decoder.decode(RenderProject.self, from: data)
        // Schema 2 adds optional effect masks/keying; schema-1 curves and edits remain unchanged.
        project.schemaVersion = RenderProject.currentSchema
        try project.validate()
        return project
    }
    public func save(_ project: RenderProject, to url: URL) throws {
        try project.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(project)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Foundation writes a sibling temporary file, then atomically replaces the destination.
        try data.write(to: url, options: .atomic)
    }
}
