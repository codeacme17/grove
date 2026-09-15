import Foundation

public struct Project: Codable, Identifiable, Hashable, Sendable {
    public var id: String { gitDirectory }
    public let name: String
    public let gitDirectory: String

    public init(name: String, gitDirectory: String) {
        self.name = name
        self.gitDirectory = gitDirectory
    }
}

public struct Worktree: Identifiable, Equatable, Sendable {
    public var id: String { path }
    public let path: String
    public let head: String?
    public let branch: String?
    public let isBare: Bool
    public let isDetached: Bool
    public let lockReason: String?
    public let pruneReason: String?
    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
    public var revision: String {
        if let branch { return branch.hasPrefix("refs/heads/") ? String(branch.dropFirst(11)) : branch }
        if isBare { return "Bare repository" }
        return head.map { String($0.prefix(8)) } ?? "No commit"
    }
}

public enum GroveError: LocalizedError, Sendable {
    case message(String)
    public var errorDescription: String? {
        switch self { case .message(let message): message }
    }
}
