import Foundation

public enum WorktreeBranch: Sendable {
    case new(name: String, base: String)
    case existing(name: String)
}

public struct WorktreeCreationOptions: Sendable {
    public let branches: [LocalBranch]
    public let defaultBaseBranch: String?
    public let destinationRoot: String

    public func suggestedDestination(for branch: String) -> String {
        let component = branch.components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_")).inverted)
            .filter { !$0.isEmpty }.joined(separator: "-")
        return URL(fileURLWithPath: destinationRoot)
            .appendingPathComponent(component.isEmpty ? "new-worktree" : String(component.prefix(100))).path
    }
}

extension WorktreeRepository {
    public func creationOptions(project: Project) async throws -> WorktreeCreationOptions {
        let trees = try await GitRepository(runner: runner).worktrees(in: project)
        guard let main = trees.first else { throw GroveError.message("No registered worktrees are available. Refresh the project.") }
        let branches = try await localBranches(project: project, worktrees: trees)
        return WorktreeCreationOptions(branches: branches,
            defaultBaseBranch: branches.first { "refs/heads/\($0.name)" == main.branch }?.name,
            destinationRoot: URL(fileURLWithPath: main.path).deletingLastPathComponent()
                .appendingPathComponent("grove-worktrees").path)
    }

    public func createWorktree(branch: WorktreeBranch, destination: String, project: Project) async throws -> Worktree {
        let options = try await creationOptions(project: project)
        var arguments = ["--git-dir", project.gitDirectory, "worktree", "add"]
        guard destination.hasPrefix("/"), !destination.utf8.contains(0) else {
            throw GroveError.message("Choose an absolute destination path.")
        }
        let target = URL(fileURLWithPath: destination).standardizedFileURL.resolvingSymlinksInPath()
        switch branch {
        case .new(let name, let base):
            guard !name.hasPrefix("-"), !name.isEmpty, !name.utf8.contains(0) else {
                throw GroveError.message("Enter a valid new branch name.")
            }
            _ = try await runner.run(["check-ref-format", "refs/heads/\(name)"])
            guard !options.branches.contains(where: { $0.name == name }) else {
                throw GroveError.message("This local branch already exists. Choose Existing Branch or a different name.")
            }
            guard options.branches.contains(where: { $0.name == base }) else {
                throw GroveError.message("The selected local base branch no longer exists. Reload the branch list.")
            }
            arguments += ["--no-track", "-b", name, "--", target.path, "refs/heads/\(base)"]
        case .existing(let name):
            guard let existing = options.branches.first(where: { $0.name == name }) else {
                throw GroveError.message("This local branch no longer exists. Reload the branch list.")
            }
            if let path = existing.checkedOutPath {
                throw GroveError.message("This branch is already checked out in \(path).")
            }
            arguments += ["--no-guess-remote", "--", target.path, name]
        }
        guard !FileManager.default.fileExists(atPath: destination),
              (try? FileManager.default.attributesOfItem(atPath: destination)) == nil,
              !FileManager.default.fileExists(atPath: target.path) else {
            throw GroveError.message("The destination already exists. Choose a new directory; Grove will not overwrite it.")
        }
        do {
            _ = try await runner.run(arguments, timeout: 120, maximumOutputBytes: 16_384)
            let trees = try await GitRepository(runner: runner).worktrees(in: project)
            guard let created = trees.first(where: {
                URL(fileURLWithPath: $0.path).resolvingSymlinksInPath().path == target.resolvingSymlinksInPath().path
            }) else {
                throw GroveError.message("Git finished, but the new worktree could not be located. Refresh the project.")
            }
            return created
        } catch {
            let name: String
            switch branch {
            case .new(let value, _), .existing(let value): name = value
            }
            throw await operationFailure(error, project: project, path: target.path, branch: name)
        }
    }


    private func validateRemovalIdentity(_ worktree: Worktree, project: Project) async throws {
        try await validate(worktree, project: project)
        let trees = try await GitRepository(runner: runner).worktrees(in: project)
        guard let current = trees.first(where: { $0.path == worktree.path }) else {
            throw GroveError.message("This worktree is no longer registered. Refresh the project.")
        }
        guard trees.first?.path != current.path else {
            throw GroveError.message("The main worktree cannot be deleted.")
        }
        guard current.lockReason == nil else { throw GroveError.message("This worktree is locked. Unlock it outside Grove before deleting it.") }
        guard current.pruneReason == nil else { throw GroveError.message("This worktree is unavailable. Stale-registration cleanup is not supported.") }
        guard !current.isDetached, let branch = current.branch else {
            throw GroveError.message("This worktree has a detached HEAD. Switch to a local branch before deleting it.")
        }
        let head = try await runner.run(["--git-dir", project.gitDirectory, "rev-parse", "--verify", branch])
        guard String(decoding: head, as: UTF8.self).trimmingCharacters(in: .newlines) == current.head else {
            throw GroveError.message("The worktree's commit is not preserved by its branch. Refresh and check it outside Grove.")
        }
    }

    public func validateRemoval(_ worktree: Worktree, project: Project) async throws {
        try await validateRemovalIdentity(worktree, project: project)
        let entries = try await runner.run(["-C", worktree.path, "ls-files", "--stage", "-z"])
        guard !entries.split(separator: 0).contains(where: { $0.starts(with: Data("160000 ".utf8)) }) else {
            throw GroveError.message("This worktree contains submodules. Remove it outside Grove after checking their contents.")
        }
        let inspection = Task.detached {
            let root = URL(fileURLWithPath: worktree.path, isDirectory: true)
            let deadline = ContinuousClock.now.advanced(by: .seconds(15))
            var inspectionError: (any Error)?
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil,
                errorHandler: { _, error in inspectionError = error; return false }) else {
                throw GroveError.message("Could not inspect this worktree for nested repositories.")
            }
            while let entry = enumerator.nextObject() as? URL {
                try Task.checkCancellation()
                guard ContinuousClock.now < deadline else {
                    throw GroveError.message("Worktree inspection took too long. Check its contents outside Grove before deleting it.")
                }
                if entry.lastPathComponent == ".git" {
                    guard entry.deletingLastPathComponent().path == root.path else {
                        throw GroveError.message("This worktree contains a nested repository. Preserve it outside Grove before deleting the worktree.")
                    }
                }
            }
            if let inspectionError { throw inspectionError }
        }
        try await withTaskCancellationHandler { try await inspection.value } onCancel: { inspection.cancel() }
        try await validateRemovalIdentity(worktree, project: project)
        let status = try await runner.run(["-C", worktree.path, "status", "--porcelain=v1", "-z",
                                          "--untracked-files=all", "--ignored", "--ignore-submodules=none"], maximumOutputBytes: 1)
        guard status.isEmpty else {
            throw GroveError.message("This worktree has local changes, untracked files, or ignored files. Preserve or remove them outside Grove before deleting it.")
        }
    }

    public func removeWorktree(_ worktree: Worktree, project: Project) async throws {
        try await validateRemoval(worktree, project: project)
        do {
            _ = try await runner.run(["--git-dir", project.gitDirectory, "worktree", "remove", "--", worktree.path],
                                     timeout: 120, maximumOutputBytes: 16_384)
        } catch {
            throw await operationFailure(error, project: project, path: worktree.path, branch: worktree.revision)
        }
    }

    private func operationFailure(_ error: any Error, project: Project, path: String, branch: String) async -> GroveError {
        let detail = error is CancellationError ? "Git operation stopped." : error.localizedDescription
        return await Task {
            var state = [detail, "Current state (no automatic rollback):"]
            do {
                let options = try await creationOptions(project: project)
                state.append("Branch \(branch): \(options.branches.contains { $0.name == branch } ? "present" : "absent")")
                let trees = try await GitRepository(runner: runner).worktrees(in: project)
                let registered = trees.contains {
                    URL(fileURLWithPath: $0.path).resolvingSymlinksInPath().path == URL(fileURLWithPath: path).resolvingSymlinksInPath().path
                }
                state.append("Worktree registration: \(registered ? "present" : "absent")")
            } catch {
                state.append("Could not read current Git state. Refresh before retrying. \(error.localizedDescription)")
            }
            let exists = (try? FileManager.default.attributesOfItem(atPath: path)) != nil
            state.append("Destination: \(exists ? "present" : "not found or inaccessible") (\(path))")
            return GroveError.message(state.joined(separator: "\n"))
        }.value
    }

}
