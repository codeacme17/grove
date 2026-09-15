import Foundation

public struct ProjectStore: Sendable {
    private let file: URL
    public init(file: URL? = nil) {
        self.file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Grove/projects.json")
    }

    public func load() throws -> [Project] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        let projects = try JSONDecoder().decode([Project].self, from: Data(contentsOf: file))
        var seen = Set<String>()
        return projects.filter { seen.insert($0.id).inserted }
    }

    public func save(_ projects: [Project]) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(projects).write(to: file, options: .atomic)
    }
}
