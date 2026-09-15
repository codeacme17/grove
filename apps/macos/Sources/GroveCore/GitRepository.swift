import Foundation

public struct GitRepository: Sendable {
    private let runner: GitRunner
    public init(runner: GitRunner = GitRunner()) { self.runner = runner }

    public func project(at folder: URL) async throws -> Project {
        let output = try await runner.run([
            "-C", folder.path, "rev-parse", "--path-format=absolute", "--git-common-dir"
        ])
        guard var path = String(data: output, encoding: .utf8), path.hasSuffix("\n") else {
            throw GroveError.message("Git returned an unsupported repository path.")
        }
        path.removeLast()
        let directory = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        let name = directory.lastPathComponent == ".git"
            ? directory.deletingLastPathComponent().lastPathComponent : directory.lastPathComponent
        return Project(name: name, gitDirectory: directory.path)
    }

    public func worktrees(in project: Project) async throws -> [Worktree] {
        let output = try await runner.run([
            "--git-dir", project.gitDirectory, "worktree", "list", "--porcelain", "-z"
        ])
        return try Self.parse(output)
    }

    public static func parse(_ data: Data) throws -> [Worktree] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw GroveError.message("This repository contains a path that is not valid UTF-8.")
        }
        guard text.isEmpty || text.hasSuffix("\0\0") else {
            throw GroveError.message("Git returned an incomplete worktree list.")
        }
        return try text.components(separatedBy: "\0\0").filter { !$0.isEmpty }.map { record in
            var fields: [String: String] = [:]
            for line in record.split(separator: "\0") {
                let pair = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
                fields[String(pair[0])] = pair.count == 2 ? String(pair[1]) : ""
            }
            guard let path = fields["worktree"], path.hasPrefix("/") else {
                throw GroveError.message("Git returned an invalid worktree path.")
            }
            return Worktree(path: path, head: fields["HEAD"], branch: fields["branch"],
                            isBare: fields["bare"] != nil, isDetached: fields["detached"] != nil,
                            lockReason: fields["locked"], pruneReason: fields["prunable"])
        }
    }
}
