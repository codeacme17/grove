import Foundation
import Testing
@testable import GroveCore

struct LifecycleFixture {
    let root: URL
    let main: URL
    let project: Project
    let git = GitRunner()

    static func create() async throws -> Self {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("grove-lifecycle-\(UUID().uuidString)")
        let main = root.appendingPathComponent("main repository")
        let git = GitRunner()
        _ = try await git.run(["init", "-b", "main", main.path])
        for (key, value) in [("user.name", "Grove Tests"), ("user.email", "tests@example.invalid"),
                             ("commit.gpgsign", "false"), ("core.hooksPath", "/dev/null")] {
            _ = try await git.run(["-C", main.path, "config", key, value])
        }
        try "original\n".write(to: main.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        _ = try await git.run(["-C", main.path, "add", "."])
        _ = try await git.run(["-C", main.path, "commit", "-m", "Initial"])
        return Self(root: root, main: main, project: try await GitRepository().project(at: main))
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }
}

@Test func lifecycleCreatesNewBranchFromSelectedLocalBase() async throws {
    let fixture = try await LifecycleFixture.create()
    defer { fixture.cleanUp() }
    let repository = WorktreeRepository()
    let destination = fixture.root.appendingPathComponent("new worktree").path
    let options = try await repository.creationOptions(project: fixture.project)
    #expect(options.defaultBaseBranch == "main")
    #expect(options.suggestedDestination(for: "feature/new-task").hasSuffix("/grove-worktrees/feature-new-task"))
    let tree = try await repository.createWorktree(branch: .new(name: "feature/new-task", base: "main"),
                                                   destination: destination, project: fixture.project)
    #expect(tree.branch == "refs/heads/feature/new-task")
    #expect(try await GitRepository().worktrees(in: fixture.project).count == 2)
    #expect(try String(contentsOf: URL(fileURLWithPath: tree.path).appendingPathComponent("tracked.txt"), encoding: .utf8) == "original\n")
}

@Test func lifecycleCreatesExistingBranchAndRechecksOccupancy() async throws {
    let fixture = try await LifecycleFixture.create()
    defer { fixture.cleanUp() }
    let repository = WorktreeRepository()
    _ = try await fixture.git.run(["-C", fixture.main.path, "branch", "available"])
    let before = try await repository.creationOptions(project: fixture.project)
    #expect(before.branches.first { $0.name == "available" }?.checkedOutPath == nil)
    let tree = try await repository.createWorktree(branch: .existing(name: "available"),
        destination: fixture.root.appendingPathComponent("existing branch").path, project: fixture.project)
    #expect(tree.branch == "refs/heads/available")
    await #expect(throws: GroveError.self) {
        try await repository.createWorktree(branch: .existing(name: "available"),
            destination: fixture.root.appendingPathComponent("occupied").path, project: fixture.project)
    }
    #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("occupied").path))
}

@Test func lifecycleDeletesExternalWorktreeButPreservesItsBranchAndCommits() async throws {
    let fixture = try await LifecycleFixture.create()
    defer { fixture.cleanUp() }
    let linked = fixture.root.appendingPathComponent("external worktree")
    _ = try await fixture.git.run(["-C", fixture.main.path, "worktree", "add", "-b", "feature", linked.path])
    try "unique commit\n".write(to: linked.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
    _ = try await fixture.git.run(["-C", linked.path, "commit", "-am", "Worktree-only commit"])
    let tree = try #require(try await GitRepository().worktrees(in: fixture.project).first { $0.revision == "feature" })
    let repository = WorktreeRepository()
    try await repository.validateRemoval(tree, project: fixture.project)
    try await repository.removeWorktree(tree, project: fixture.project)
    #expect(!FileManager.default.fileExists(atPath: linked.path))
    #expect(try await GitRepository().worktrees(in: fixture.project).count == 1)
    #expect(try await repository.creationOptions(project: fixture.project).branches.contains { $0.name == "feature" })
    let restored = try await repository.createWorktree(branch: .existing(name: "feature"), destination: linked.path, project: fixture.project)
    #expect(restored.head == tree.head)
    #expect(try String(contentsOf: linked.appendingPathComponent("tracked.txt"), encoding: .utf8) == "unique commit\n")
}

@Test(arguments: ["staged", "unstaged", "untracked", "ignored", "nested", "submodule", "locked", "detached", "missing", "main", "bare", "wrong-project"])
func lifecycleRejectsUnsafeRemovalEvenAfterConfirmation(kind: String) async throws {
    let fixture = try await LifecycleFixture.create()
    defer { fixture.cleanUp() }
    let repository = WorktreeRepository()
    let linked = fixture.root.appendingPathComponent("protected worktree")
    var tree = try await repository.createWorktree(branch: .new(name: "protected", base: "main"), destination: linked.path, project: fixture.project)
    var project = fixture.project
    try await repository.validateRemoval(tree, project: project)
    switch kind {
    case "staged", "unstaged":
        try "preserve changes".write(to: linked.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        if kind == "staged" { _ = try await fixture.git.run(["-C", linked.path, "add", "."]) }
    case "untracked":
        try "preserve new file".write(to: linked.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
    case "ignored":
        try "secret.txt\n".write(to: URL(fileURLWithPath: project.gitDirectory).appendingPathComponent("info/exclude"), atomically: true, encoding: .utf8)
        try "preserve ignored file".write(to: linked.appendingPathComponent("secret.txt"), atomically: true, encoding: .utf8)
    case "nested":
        let nested = linked.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "tracked nested content".write(to: nested.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        _ = try await fixture.git.run(["-C", linked.path, "add", "."])
        _ = try await fixture.git.run(["-C", linked.path, "commit", "-m", "Track nested directory"])
        _ = try await fixture.git.run(["init", nested.path])
    case "submodule":
        _ = try await fixture.git.run(["-C", linked.path, "update-index", "--add", "--cacheinfo", "160000,\(tree.head!),module"])
        _ = try await fixture.git.run(["-C", linked.path, "commit", "-m", "Record uninitialized submodule"])
    case "locked":
        _ = try await fixture.git.run(["-C", fixture.main.path, "worktree", "lock", linked.path])
    case "detached":
        _ = try await fixture.git.run(["-C", linked.path, "switch", "--detach"])
    case "missing": try FileManager.default.removeItem(at: linked)
    case "main": tree = try #require(try await GitRepository().worktrees(in: project).first)
    case "bare":
        let bare = fixture.root.appendingPathComponent("bare.git")
        _ = try await fixture.git.run(["clone", "--bare", fixture.main.path, bare.path])
        project = try await GitRepository().project(at: bare)
        tree = try #require(try await GitRepository().worktrees(in: project).first)
    case "wrong-project":
        project = Project(name: "Wrong", gitDirectory: fixture.root.appendingPathComponent("other.git").path)
    default: break
    }
    await #expect(throws: (any Error).self) { try await repository.removeWorktree(tree, project: project) }
    if kind != "missing" { #expect(FileManager.default.fileExists(atPath: tree.path)) }
}

@Test(arguments: ["empty-directory", "nonempty-directory", "dangling-symlink", "invalid-name", "existing-name", "missing-base", "remote-only", "occupied", "relative-path"])
func lifecycleRejectsConflictingCreationWithoutOverwriting(kind: String) async throws {
    let fixture = try await LifecycleFixture.create()
    defer { fixture.cleanUp() }
    let repository = WorktreeRepository()
    var destination = fixture.root.appendingPathComponent("destination").path
    var branch = WorktreeBranch.new(name: "new-task", base: "main")
    _ = try await repository.creationOptions(project: fixture.project)
    switch kind {
    case "empty-directory", "nonempty-directory":
        try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
        if kind == "nonempty-directory" {
            try "keep me".write(toFile: destination + "/marker", atomically: true, encoding: .utf8)
        }
    case "dangling-symlink": try FileManager.default.createSymbolicLink(atPath: destination, withDestinationPath: fixture.root.appendingPathComponent("absent").path)
    case "invalid-name": branch = .new(name: "bad..branch", base: "main")
    case "existing-name": branch = .new(name: "main", base: "main")
    case "missing-base": branch = .new(name: "new-task", base: "deleted")
    case "remote-only":
        _ = try await fixture.git.run(["-C", fixture.main.path, "update-ref", "refs/remotes/origin/remote-only", "HEAD"])
        branch = .existing(name: "remote-only")
    case "occupied": branch = .existing(name: "main")
    case "relative-path": destination = "relative-worktree"
    default: break
    }
    await #expect(throws: (any Error).self) {
        try await repository.createWorktree(branch: branch, destination: destination, project: fixture.project)
    }
    #expect(try await GitRepository().worktrees(in: fixture.project).count == 1)
    #expect(try await repository.creationOptions(project: fixture.project).branches.map(\.name) == ["main"])
    if kind == "nonempty-directory" {
        #expect(try String(contentsOfFile: destination + "/marker", encoding: .utf8) == "keep me")
    }
}

@Test func lifecycleRequiresExplicitBaseWhenMainIsDetached() async throws {
    let fixture = try await LifecycleFixture.create()
    defer { fixture.cleanUp() }
    _ = try await fixture.git.run(["-C", fixture.main.path, "switch", "--detach"])
    let options = try await WorktreeRepository().creationOptions(project: fixture.project)
    #expect(options.defaultBaseBranch == nil)
    #expect(options.branches.map(\.name) == ["main"])
    let suggestion = options.suggestedDestination(for: "../../task")
    #expect(URL(fileURLWithPath: suggestion).lastPathComponent == "task")
    #expect(URL(fileURLWithPath: suggestion).deletingLastPathComponent().lastPathComponent == "grove-worktrees")
}

@Test func lifecycleReportsPartialCreationWithoutRemovingItsBranchOrDirectory() async throws {
    let fixture = try await LifecycleFixture.create()
    defer { fixture.cleanUp() }
    let hooks = fixture.root.appendingPathComponent("hooks")
    try FileManager.default.createDirectory(at: hooks, withIntermediateDirectories: true)
    let hook = hooks.appendingPathComponent("post-checkout")
    try "#!/bin/sh\nexit 1\n".write(to: hook, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: hook.path)
    _ = try await fixture.git.run(["-C", fixture.main.path, "config", "core.hooksPath", hooks.path])
    do {
        _ = try await WorktreeRepository().createWorktree(branch: .new(name: "partial", base: "main"),
            destination: fixture.root.appendingPathComponent("partial").path, project: fixture.project)
        Issue.record("Expected the post-checkout hook to fail")
    } catch {
        #expect(error.localizedDescription.contains("Branch partial: present"))
        #expect(error.localizedDescription.contains("Destination: present"))
        #expect(error.localizedDescription.contains("Worktree registration: present"))
    }
    #expect(try await GitRepository().worktrees(in: fixture.project).count == 2)
}
