import Foundation
import Testing
@testable import GroveCore

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("grove-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func discoversWorktreesAndCanonicalIdentity() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let main = root.appendingPathComponent("project with spaces")
    let linked = root.appendingPathComponent("agent\nworktree")
    let detached = root.appendingPathComponent("detached")
    let stale = root.appendingPathComponent("stale")
    let git = GitRunner()
    _ = try await git.run(["init", "-b", "main", main.path])
    _ = try await git.run(["-C", main.path, "-c", "user.name=Grove Tests", "-c", "user.email=tests@example.invalid", "-c", "commit.gpgsign=false", "commit", "--allow-empty", "-m", "Initial"])
    _ = try await git.run(["-C", main.path, "worktree", "add", "-b", "feat/example", linked.path])
    _ = try await git.run(["-C", main.path, "worktree", "add", "--detach", detached.path])
    _ = try await git.run(["-C", main.path, "worktree", "add", "-b", "stale", stale.path])
    _ = try await git.run(["-C", main.path, "worktree", "lock", "--reason", "Agent workspace", linked.path])
    try FileManager.default.removeItem(at: stale)

    let repository = GitRepository()
    let project = try await repository.project(at: main)
    let linkedProject = try await repository.project(at: linked)
    #expect(project == linkedProject)
    let child = linked.appendingPathComponent("nested")
    try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
    #expect(try await repository.project(at: child) == project)
    let alias = root.appendingPathComponent("alias")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: linked)
    #expect(try await repository.project(at: alias) == project)

    let worktrees = try await repository.worktrees(in: project)
    #expect(worktrees.count == 4)
    #expect(worktrees[0].revision == "main")
    #expect(worktrees.first { $0.name == linked.lastPathComponent }?.lockReason == "Agent workspace")
    #expect(worktrees.first { $0.name == linked.lastPathComponent }?.revision == "feat/example")
    #expect(worktrees.first { $0.name == "detached" }?.isDetached == true)
    #expect(worktrees.first { $0.name == "stale" }?.pruneReason != nil)
    #expect(worktrees.contains { $0.path.contains("\n") })
}

@Test func handlesUnbornAndBareRepositories() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let git = GitRunner()
    let repository = GitRepository()
    _ = try await git.run(["init", "-b", "main", root.appendingPathComponent("unborn").path])
    let unborn = try await repository.project(at: root.appendingPathComponent("unborn"))
    #expect(try await repository.worktrees(in: unborn).first?.revision == "main")
    _ = try await git.run(["init", "--bare", root.appendingPathComponent("bare.git").path])
    let bare = try await repository.project(at: root.appendingPathComponent("bare.git"))
    #expect(try await repository.worktrees(in: bare).first?.isBare == true)
}

@Test func rejectsNonRepository() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    await #expect(throws: GroveError.self) { try await GitRepository().project(at: root) }
}

@Test func parsesFlagsAndRejectsDamagedOutput() throws {
    let data = Data("worktree /tmp/project\0HEAD abc12345678\0detached\0locked\0\0".utf8)
    let tree = try #require(GitRepository.parse(data).first)
    #expect(tree.revision == "abc12345")
    #expect(tree.lockReason == "")
    #expect(tree.isDetached)
    #expect(throws: GroveError.self) { try GitRepository.parse(Data("worktree /tmp/cutoff".utf8)) }
    #expect(throws: GroveError.self) { try GitRepository.parse(Data([0xff])) }
}

@Test func persistsProjectsAndPreservesMalformedData() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("settings/projects.json")
    let store = ProjectStore(file: file)
    let first = Project(name: "same", gitDirectory: "/one/.git")
    let second = Project(name: "same", gitDirectory: "/two/.git")
    #expect(try store.load().isEmpty)
    try store.save([first, first, second])
    #expect(try store.load() == [first, second])
    try store.save([second])
    #expect(try store.load() == [second])
    let malformed = Data("{damaged".utf8)
    try malformed.write(to: file)
    #expect(throws: (any Error).self) { try store.load() }
    #expect(try Data(contentsOf: file) == malformed)
}

@Test func timesOutAndCancelsProcesses() async throws {
    let sleep = URL(fileURLWithPath: "/bin/sleep")
    await #expect(throws: GroveError.self) {
        try await GitRunner(executable: sleep, timeout: 0.1).run(["5"])
    }
    let task = Task { try await GitRunner(executable: sleep).run(["5"]) }
    try await Task.sleep(for: .milliseconds(100))
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
}
