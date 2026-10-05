import Foundation
import GroveCore
import Testing
@testable import Grove

@MainActor private func waitForLiveChange(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(8))
    while !condition(), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(25))
    }
    try #require(condition())
}

@MainActor @Test func liveWorktreesFollowExternalGitOperationsWithoutManualRefresh() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("grove-live-worktrees-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let main = root.appendingPathComponent("main")
    let linked = root.appendingPathComponent("outside/linked")
    let git = GitRunner()
    _ = try await git.run(["init", "-b", "main", main.path])
    for (key, value) in [("user.name", "Grove Tests"), ("user.email", "tests@example.invalid"),
                         ("commit.gpgsign", "false"), ("core.hooksPath", "/dev/null")] {
        _ = try await git.run(["-C", main.path, "config", key, value])
    }
    _ = try await git.run(["-C", main.path, "commit", "--allow-empty", "-m", "Initial"])
    let project = try await GitRepository().project(at: main)
    let store = ProjectStore(file: root.appendingPathComponent("projects.json"))
    try store.save([project])
    let model = WorkspaceModel(store: store)
    let observation = Task { await model.observeWorktrees() }
    defer { observation.cancel() }
    try await waitForLiveChange { model.worktrees.count == 1 }
    #expect(!model.isLoading)

    _ = try await git.run(["-C", main.path, "switch", "-c", "renamed"])
    try await waitForLiveChange { model.worktrees.first?.branch == "refs/heads/renamed" }
    _ = try await git.run(["-C", main.path, "worktree", "add", "-b", "feature", linked.path])
    try await waitForLiveChange { model.worktrees.count == 2 }
    _ = try await git.run(["-C", linked.path, "switch", "--detach"])
    try await waitForLiveChange { model.worktrees.last?.isDetached == true }
    let head = model.worktrees.last?.head
    _ = try await git.run(["-C", linked.path, "commit", "--allow-empty", "-m", "Linked update"])
    try await waitForLiveChange { model.worktrees.last?.head != head }
    _ = try await git.run(["-C", main.path, "worktree", "lock", "--reason", "Keep", linked.path])
    try await waitForLiveChange { model.worktrees.last?.lockReason == "Keep" }
    _ = try await git.run(["-C", main.path, "worktree", "unlock", linked.path])
    try await waitForLiveChange { model.worktrees.last?.lockReason == nil }
    _ = try await git.run(["-C", main.path, "worktree", "remove", linked.path])
    try await waitForLiveChange { model.worktrees.count == 1 }

    // Index changes must not restart all diff observers when the list is unchanged.
    let timestamp = model.updatedAt
    try "new file\n".write(to: main.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
    _ = try await git.run(["-C", main.path, "add", "new.txt"])
    try await Task.sleep(for: .seconds(1))
    #expect(model.updatedAt == timestamp)
    #expect(!model.isLoading)
    #expect(model.loadError == nil)

    observation.cancel()
    await observation.value
    _ = try await git.run(["-C", main.path, "switch", "-c", "after-stop"])
    try await Task.sleep(for: .milliseconds(600))
    #expect(model.worktrees.first?.branch == "refs/heads/renamed")
    #expect(model.updatedAt == timestamp)
}

@MainActor @Test func liveWorktreesSwitchProjectsAndIgnoreThePreviousRepository() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("grove-live-selection-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let git = GitRunner()
    var projects: [Project] = []
    for name in ["first", "second"] {
        let folder = root.appendingPathComponent(name)
        _ = try await git.run(["init", "-b", name, folder.path])
        projects.append(try await GitRepository().project(at: folder))
    }
    let store = ProjectStore(file: root.appendingPathComponent("projects.json"))
    try store.save(projects)
    let model = WorkspaceModel(store: store)
    let firstObservation = Task { await model.observeWorktrees() }
    defer { firstObservation.cancel() }
    try await waitForLiveChange { model.worktrees.first?.branch == "refs/heads/first" }

    model.selection = projects[1].id
    firstObservation.cancel()
    await firstObservation.value
    let secondObservation = Task { await model.observeWorktrees() }
    defer { secondObservation.cancel() }
    try await waitForLiveChange { model.worktrees.first?.branch == "refs/heads/second" }
    let timestamp = model.updatedAt
    _ = try await git.run(["-C", root.appendingPathComponent("first").path, "switch", "-c", "old-project"])
    try await Task.sleep(for: .milliseconds(600))
    #expect(model.worktrees.first?.branch == "refs/heads/second")
    #expect(model.updatedAt == timestamp)

    _ = try await git.run(["-C", root.appendingPathComponent("second").path, "switch", "-c", "current-project"])
    try await waitForLiveChange { model.worktrees.first?.branch == "refs/heads/current-project" }
    #expect(model.displayedProject?.id == projects[1].id)
}

@MainActor @Test func liveChangesFollowLinkedWorktreeEditsIndexRenamesAndCancellation() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("grove-live-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let main = root.appendingPathComponent("main")
    let linked = root.appendingPathComponent("linked")
    let git = GitRunner()
    _ = try await git.run(["init", "-b", "main", main.path])
    for (key, value) in [("user.name", "Grove Tests"), ("user.email", "tests@example.invalid"),
                         ("commit.gpgsign", "false"), ("core.hooksPath", "/dev/null")] {
        _ = try await git.run(["-C", main.path, "config", key, value])
    }
    try "original\n".write(to: main.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
    _ = try await git.run(["-C", main.path, "add", "."])
    _ = try await git.run(["-C", main.path, "commit", "-m", "Initial"])
    _ = try await git.run(["-C", main.path, "worktree", "add", "-b", "feature", linked.path])
    let project = try await GitRepository().project(at: linked)
    let worktree = try #require(try await GitRepository().worktrees(in: project).first { $0.name == "linked" })
    let state = WorktreeChangesModel()
    let preview = FileDiffModel()
    var refreshes = 0
    let observation = Task {
        await state.observe(in: worktree, project: project) {
            refreshes += 1
            if let change = state.changes?.first {
                await preview.load(FileDiffSelection(change: change, worktree: worktree, project: project))
            }
        }
    }
    defer { observation.cancel() }
    try await waitForLiveChange { state.changedFileCount == 0 }

    let tracked = linked.appendingPathComponent("tracked.txt")
    try "first edit\n".write(to: tracked, atomically: true, encoding: .utf8)
    try await waitForLiveChange { state.changedFileCount == 1 && preview.snapshot?.content.text.contains("+first edit") == true }
    try "second edit\n".write(to: tracked, atomically: true, encoding: .utf8)
    try await waitForLiveChange { preview.snapshot?.content.text.contains("+second edit") == true }
    #expect(state.changedFileCount == 1)

    // The linked worktree's index lives outside the watched working directory.
    _ = try await git.run(["-C", linked.path, "add", "tracked.txt"])
    try await waitForLiveChange { preview.snapshot?.selection.change.section == .staged }
    #expect(state.changedFileCount == 1)
    _ = try await git.run(["-C", linked.path, "mv", "tracked.txt", "renamed.txt"])
    try await waitForLiveChange { preview.snapshot?.selection.change.path == "renamed.txt" }
    _ = try await git.run(["-C", linked.path, "commit", "-m", "Update"])
    try await waitForLiveChange { state.changedFileCount == 0 }

    let added = linked.appendingPathComponent("new.txt")
    try "new file\n".write(to: added, atomically: true, encoding: .utf8)
    try await waitForLiveChange { state.changes?.first?.section == .untracked && preview.snapshot?.selection.change.path == "new.txt" }
    try FileManager.default.removeItem(at: added)
    try await waitForLiveChange { state.changedFileCount == 0 }

    observation.cancel()
    await observation.value
    let refreshesAtStop = refreshes
    try "after stop\n".write(to: added, atomically: true, encoding: .utf8)
    try await Task.sleep(for: .milliseconds(600))
    #expect(refreshes == refreshesAtStop)
    #expect(!state.isLoading)
}
