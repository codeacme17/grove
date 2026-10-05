import Foundation
import GroveCore
import Testing
@testable import Grove

@MainActor @Test func pullResultsUseToastsAndPreserveLocalChangesOnFailure() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("grove-pull-feedback-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source")
    let remote = root.appendingPathComponent("origin.git")
    let checkout = root.appendingPathComponent("checkout")
    let git = GitRunner()
    _ = try await git.run(["init", "-b", "main", source.path])
    for (key, value) in [("user.name", "Grove Tests"), ("user.email", "tests@example.invalid"),
                         ("commit.gpgsign", "false"), ("core.hooksPath", "/dev/null")] {
        _ = try await git.run(["-C", source.path, "config", key, value])
    }
    try "original\n".write(to: source.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
    _ = try await git.run(["-C", source.path, "add", "."])
    _ = try await git.run(["-C", source.path, "commit", "-m", "Initial"])
    _ = try await git.run(["clone", "--bare", source.path, remote.path])
    _ = try await git.run(["clone", remote.path, checkout.path])
    _ = try await git.run(["-C", checkout.path, "config", "core.hooksPath", "/dev/null"])
    let project = try await GitRepository().project(at: checkout)
    let worktree = try #require(try await GitRepository().worktrees(in: project).first)
    let store = ProjectStore(file: root.appendingPathComponent("projects.json"))
    try store.save([project])
    let model = WorkspaceModel(store: store)

    try "remote update\n".write(to: source.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
    _ = try await git.run(["-C", source.path, "add", "."])
    _ = try await git.run(["-C", source.path, "commit", "-m", "Remote update"])
    _ = try await git.run(["-C", source.path, "push", remote.path, "main"])
    await model.pull(worktree, project: project)
    let success = try #require(model.toast)
    #expect(!success.isError)
    #expect(success.message.contains(worktree.name))
    #expect(success.detail == nil)
    #expect(model.worktreeMessages[worktree.path] == nil)
    #expect(model.actionError == nil)
    #expect(!model.isPerformingGitOperation)
    #expect(model.loadError == nil)
    let file = checkout.appendingPathComponent("tracked.txt")
    #expect(try String(contentsOf: file, encoding: .utf8) == "remote update\n")
    let current = try #require(model.worktrees.first)
    #expect(current.head != worktree.head)

    await model.pull(current, project: project)
    let repeated = try #require(model.toast)
    #expect(repeated.id != success.id)
    #expect(!repeated.isError)
    // A previous toast's expiry must not clear the newer notification.
    model.dismissToast(id: success.id)
    #expect(model.toast?.id == repeated.id)

    try "keep local edits\n".write(to: file, atomically: true, encoding: .utf8)
    await model.pull(current, project: project)
    let failure = try #require(model.toast)
    #expect(failure.isError)
    #expect(failure.message.contains(worktree.name))
    #expect(failure.detail?.contains("local changes") == true)
    #expect(model.worktreeMessages[worktree.path] == nil)
    #expect(model.actionError == nil)
    #expect(!model.isPerformingGitOperation)
    #expect(model.loadError == nil)
    #expect(try String(contentsOf: file, encoding: .utf8) == "keep local edits\n")
    #expect(model.worktrees.first?.head == current.head)

    try "remote update\n".write(to: file, atomically: true, encoding: .utf8)
    _ = try await git.run(["-C", checkout.path, "branch", "--unset-upstream"])
    await model.pull(current, project: project)
    let missingUpstream = try #require(model.toast)
    #expect(missingUpstream.isError)
    #expect(missingUpstream.detail?.isEmpty == false)
    #expect(model.actionError == nil)
    #expect(model.worktreeMessages[worktree.path] == nil)
    model.dismissToast(id: missingUpstream.id)
    #expect(model.toast == nil)
}
