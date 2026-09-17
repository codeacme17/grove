import Foundation
import GroveCore
import Testing
@testable import Grove

@MainActor @Test func changedFileCountTracksCleanDirtyAndCleanAgainWithoutDoubleCounting() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("grove-count-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let git = GitRunner()
    _ = try await git.run(["init", "-b", "main", folder.path])
    let project = try await GitRepository().project(at: folder)
    let worktree = try #require(try await GitRepository().worktrees(in: project).first)
    let model = WorktreeChangesModel()
    #expect(model.changedFileCount == nil)

    await model.load(in: worktree, project: project)
    #expect(model.errorMessage == nil)
    #expect(model.changedFileCount == 0)

    let tracked = folder.appendingPathComponent("tracked.txt")
    let untracked = folder.appendingPathComponent("new.txt")
    try "staged\n".write(to: tracked, atomically: true, encoding: .utf8)
    _ = try await git.run(["-C", folder.path, "add", "tracked.txt"])
    try "staged\nunstaged\n".write(to: tracked, atomically: true, encoding: .utf8)
    try "new\n".write(to: untracked, atomically: true, encoding: .utf8)
    await model.load(in: worktree, project: project)
    #expect(model.errorMessage == nil)
    #expect(model.changes?.count == 3)
    #expect(model.changedFileCount == 2)

    let wrongProject = Project(name: "Wrong", gitDirectory: folder.appendingPathComponent("other.git").path)
    await model.load(in: worktree, project: wrongProject)
    #expect(model.errorMessage != nil)
    #expect(model.changedFileCount == 2)
    let unreadModel = WorktreeChangesModel()
    await unreadModel.load(in: worktree, project: wrongProject)
    #expect(unreadModel.errorMessage != nil)
    #expect(unreadModel.changedFileCount == nil)

    _ = try await git.run(["-C", folder.path, "rm", "--cached", "-f", "tracked.txt"])
    try FileManager.default.removeItem(at: tracked)
    try FileManager.default.removeItem(at: untracked)
    await model.load(in: worktree, project: project)
    #expect(model.errorMessage == nil)
    #expect(model.changedFileCount == 0)
}
