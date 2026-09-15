import Foundation

public struct LocalBranch: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let checkedOutPath: String?
}

public struct DiffContent: Sendable {
    public let text: String
    public let isTruncated: Bool
}

public struct WorktreeRepository: Sendable {
    private let runner: GitRunner
    private let diffLimit = 200_000

    public init(runner: GitRunner = GitRunner()) { self.runner = runner }

    public func branches(in worktree: Worktree, project: Project) async throws -> [LocalBranch] {
        try await validate(worktree, project: project)
        let data = try await runner.run(["-C", worktree.path, "for-each-ref", "--sort=refname",
                                         "--format=%(refname)", "refs/heads/"])
        let trees = try await GitRepository(runner: runner).worktrees(in: project)
        return String(decoding: data, as: UTF8.self).split(separator: "\n").map { ref in
            LocalBranch(name: String(ref.dropFirst("refs/heads/".count)),
                        checkedOutPath: trees.first { $0.branch == String(ref) }?.path)
        }
    }

    public func pull(_ worktree: Worktree, project: Project) async throws -> String {
        try await validate(worktree, project: project)
        try await requireClean(worktree)
        _ = try await runner.run(["-C", worktree.path, "symbolic-ref", "--quiet", "HEAD"])
        _ = try await runner.run(["-C", worktree.path, "rev-parse", "--verify", "@{upstream}"])
        let data = try await runner.run(["-C", worktree.path, "pull", "--ff-only", "--no-rebase",
                                         "--no-autostash", "--no-recurse-submodules"],
                                        timeout: 120, maximumOutputBytes: 16_384)
        let message = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "Pull completed." : message
    }

    public func switchBranch(_ name: String, in worktree: Worktree, project: Project) async throws {
        let available = try await branches(in: worktree, project: project)
        guard let branch = available.first(where: { $0.name == name }) else {
            throw GroveError.message("This local branch no longer exists. Reload the branch list.")
        }
        if let path = branch.checkedOutPath, path != worktree.path {
            throw GroveError.message("This branch is already checked out in \(path).")
        }
        try await requireClean(worktree)
        _ = try await runner.run(["-C", worktree.path, "switch", "--no-guess", "--no-recurse-submodules", "--", name])
    }

    public func changes(in worktree: Worktree, project: Project) async throws -> [WorktreeChange] {
        try await validate(worktree, project: project)
        let data = try await runner.run(["-C", worktree.path, "status", "--porcelain=v1", "-z",
                                         "--untracked-files=all", "--ignore-submodules=none", "--renames"])
        return try WorktreeChange.parseStatus(data)
    }

    public func diff(for change: WorktreeChange, in worktree: Worktree, project: Project) async throws -> DiffContent {
        try await validate(worktree, project: project)
        var options = ["--literal-pathspecs", "-C", worktree.path, "diff", "--no-color", "--no-ext-diff",
                       "--no-textconv", "--no-relative", "--ignore-submodules=none"]
        if change.section == .untracked {
            if change.path.hasSuffix("/") {
                return DiffContent(text: "Untracked directory: \(change.path)\n", isTruncated: false)
            }
            return content(try await runner.run(options + ["--no-index", "--", "/dev/null", change.path],
                                                 acceptedExitCodes: [0, 1], maximumOutputBytes: diffLimit + 1))
        }
        options += ["--no-exit-code", "--find-renames"]
        if change.section == .staged { options.append("--cached") }
        options.append("--")
        if let originalPath = change.originalPath { options.append(originalPath) }
        options.append(change.path)
        return content(try await runner.run(options, maximumOutputBytes: diffLimit + 1))
    }

    private func content(_ data: Data) -> DiffContent {
        DiffContent(text: String(decoding: data.prefix(diffLimit), as: UTF8.self), isTruncated: data.count > diffLimit)
    }

    private func requireClean(_ worktree: Worktree) async throws {
        let status = try await runner.run(["-C", worktree.path, "status", "--porcelain=v1", "-z",
                                           "--untracked-files=normal", "--ignore-submodules=none"], maximumOutputBytes: 1)
        guard status.isEmpty else {
            throw GroveError.message("This worktree has local changes. Commit or stash them before pulling or switching branches.")
        }
    }

    private func validate(_ worktree: Worktree, project: Project) async throws {
        guard !worktree.isBare else { throw GroveError.message("This operation requires a working tree.") }
        let repository = GitRepository(runner: runner)
        let actual = try await repository.project(at: URL(fileURLWithPath: worktree.path))
        guard actual.id == project.id else {
            throw GroveError.message("This path no longer belongs to the selected project. Refresh the worktree list.")
        }
        let data = try await runner.run(["-C", worktree.path, "rev-parse", "--show-toplevel"])
        guard var path = String(data: data, encoding: .utf8), path.hasSuffix("\n") else {
            throw GroveError.message("Git returned an unsupported worktree path.")
        }
        path.removeLast()
        let actualRoot = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        let expectedRoot = URL(fileURLWithPath: worktree.path).standardizedFileURL.resolvingSymlinksInPath()
        guard actualRoot == expectedRoot else {
            throw GroveError.message("The registered worktree is no longer present at this path. Refresh the worktree list.")
        }
    }
}
