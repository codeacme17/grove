import Foundation
import Testing
@testable import GroveCore

private struct WorktreeFixture {
    let root: URL
    let main: URL
    let linked: URL
    let remote: URL
    let project: Project
    let worktree: Worktree
    let git = GitRunner()

    static func create() async throws -> WorktreeFixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("grove-actions-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let main = root.appendingPathComponent("main worktree")
        let linked = root.appendingPathComponent("linked worktree")
        let remote = root.appendingPathComponent("origin.git")
        let git = GitRunner()
        _ = try await git.run(["init", "-b", "main", main.path])
        try await configure(main)
        try "original\n".write(to: main.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        _ = try await git.run(["-C", main.path, "add", "."])
        _ = try await git.run(["-C", main.path, "commit", "-m", "Initial"])
        _ = try await git.run(["clone", "--bare", main.path, remote.path])
        _ = try await git.run(["-C", main.path, "remote", "add", "origin", remote.path])
        _ = try await git.run(["-C", main.path, "fetch", "origin"])
        _ = try await git.run(["-C", main.path, "worktree", "add", "-b", "feature", linked.path])
        let repository = GitRepository()
        let project = try await repository.project(at: main)
        let tree = try #require(try await repository.worktrees(in: project).first { $0.name == "linked worktree" })
        return WorktreeFixture(root: root, main: main, linked: linked, remote: remote, project: project, worktree: tree)
    }

    static func configure(_ folder: URL) async throws {
        for (key, value) in [("user.name", "Grove Tests"), ("user.email", "tests@example.invalid"),
                             ("commit.gpgsign", "false"), ("core.hooksPath", "/dev/null")] {
            _ = try await GitRunner().run(["-C", folder.path, "config", key, value])
        }
    }

    func publishRemoteChange() async throws {
        let writer = root.appendingPathComponent("writer")
        _ = try await git.run(["clone", remote.path, writer.path])
        try await Self.configure(writer)
        try "remote update\n".write(to: writer.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        _ = try await git.run(["-C", writer.path, "add", "."])
        _ = try await git.run(["-C", writer.path, "commit", "-m", "Remote update"])
        _ = try await git.run(["-C", writer.path, "push", "origin", "main"])
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }
}

@Test func diffSeparatesStagedUnstagedAndUntrackedWithoutChangingTheIndex() async throws {
    let fixture = try await WorktreeFixture.create()
    defer { fixture.cleanUp() }
    let file = fixture.linked.appendingPathComponent("tracked.txt")
    try "staged version\n".write(to: file, atomically: true, encoding: .utf8)
    _ = try await fixture.git.run(["-C", fixture.linked.path, "add", "tracked.txt"])
    try "staged version\nunstaged addition\n".write(to: file, atomically: true, encoding: .utf8)
    try "new text\n".write(to: fixture.linked.appendingPathComponent("new\nfile.txt"), atomically: true, encoding: .utf8)
    try Data([0, 1, 2, 0]).write(to: fixture.linked.appendingPathComponent("binary.bin"))
    let before = try await fixture.git.run(["-C", fixture.linked.path, "status", "--porcelain=v1", "-z"])
    let indexBefore = try await fixture.git.run(["-C", fixture.linked.path, "ls-files", "--stage", "-z"])

    let repository = WorktreeRepository()
    let changes = try await repository.changes(in: fixture.worktree, project: fixture.project)
    let staged = try #require(changes.first { $0.section == .staged && $0.path == "tracked.txt" })
    let unstaged = try #require(changes.first { $0.section == .unstaged && $0.path == "tracked.txt" })
    let untracked = try #require(changes.first { $0.path == "new\nfile.txt" })
    let binary = try #require(changes.first { $0.path == "binary.bin" })
    let stagedDiff = try await repository.diff(for: staged, in: fixture.worktree, project: fixture.project)
    let unstagedDiff = try await repository.diff(for: unstaged, in: fixture.worktree, project: fixture.project)
    #expect(stagedDiff.text.contains("+staged version"))
    #expect(!stagedDiff.text.contains("unstaged addition"))
    #expect(unstagedDiff.text.contains("+unstaged addition"))
    #expect(changes.filter { $0.section == .untracked }.count == 2)
    #expect(try await repository.diff(for: untracked, in: fixture.worktree, project: fixture.project).text.contains("+new text"))
    #expect(try await repository.diff(for: binary, in: fixture.worktree, project: fixture.project).text.contains("Binary files"))
    #expect(try await fixture.git.run(["-C", fixture.linked.path, "status", "--porcelain=v1", "-z"]) == before)
    #expect(try await fixture.git.run(["-C", fixture.linked.path, "ls-files", "--stage", "-z"]) == indexBefore)
}

@Test func switchesOnlyTheTargetWorktreeAndRejectsOccupiedOrDirtyBranches() async throws {
    let fixture = try await WorktreeFixture.create()
    defer { fixture.cleanUp() }
    let repository = WorktreeRepository()
    _ = try await fixture.git.run(["-C", fixture.main.path, "branch", "available"])
    let branches = try await repository.branches(in: fixture.worktree, project: fixture.project)
    #expect(branches.first { $0.name == "main" }?.checkedOutPath != nil)
    #expect(branches.first { $0.name == "available" }?.checkedOutPath == nil)
    await #expect(throws: GroveError.self) {
        try await repository.switchBranch("main", in: fixture.worktree, project: fixture.project)
    }
    try await repository.switchBranch("available", in: fixture.worktree, project: fixture.project)
    #expect(try await fixture.git.run(["-C", fixture.linked.path, "branch", "--show-current"]) == Data("available\n".utf8))
    #expect(try await fixture.git.run(["-C", fixture.main.path, "branch", "--show-current"]) == Data("main\n".utf8))
    let file = fixture.linked.appendingPathComponent("tracked.txt")
    try "keep my edits\n".write(to: file, atomically: true, encoding: .utf8)
    await #expect(throws: GroveError.self) {
        try await repository.switchBranch("feature", in: fixture.worktree, project: fixture.project)
    }
    #expect(try String(contentsOf: file, encoding: .utf8) == "keep my edits\n")
    #expect(try await fixture.git.run(["-C", fixture.linked.path, "branch", "--show-current"]) == Data("available\n".utf8))
}

@Test func pullFastForwardsOnlyTheSelectedWorktree() async throws {
    let fixture = try await WorktreeFixture.create()
    defer { fixture.cleanUp() }
    _ = try await fixture.git.run(["-C", fixture.linked.path, "branch", "--set-upstream-to=origin/main", "feature"])
    _ = try await fixture.git.run(["-C", fixture.linked.path, "config", "pull.rebase", "true"])
    try await fixture.publishRemoteChange()
    _ = try await WorktreeRepository().pull(fixture.worktree, project: fixture.project)
    #expect(try String(contentsOf: fixture.linked.appendingPathComponent("tracked.txt"), encoding: .utf8) == "remote update\n")
    #expect(try String(contentsOf: fixture.main.appendingPathComponent("tracked.txt"), encoding: .utf8) == "original\n")
    #expect(try await fixture.git.run(["-C", fixture.linked.path, "rev-parse", "HEAD"]) == fixture.git.run(["-C", fixture.linked.path, "rev-parse", "origin/main"]))
}

@Test func pullRejectsDivergenceAndPreservesLocalChanges() async throws {
    let fixture = try await WorktreeFixture.create()
    defer { fixture.cleanUp() }
    _ = try await fixture.git.run(["-C", fixture.linked.path, "branch", "--set-upstream-to=origin/main", "feature"])
    try "local commit\n".write(to: fixture.linked.appendingPathComponent("local.txt"), atomically: true, encoding: .utf8)
    _ = try await fixture.git.run(["-C", fixture.linked.path, "add", "."])
    _ = try await fixture.git.run(["-C", fixture.linked.path, "commit", "-m", "Local update"])
    let head = try await fixture.git.run(["-C", fixture.linked.path, "rev-parse", "HEAD"])
    try await fixture.publishRemoteChange()
    await #expect(throws: GroveError.self) { try await WorktreeRepository().pull(fixture.worktree, project: fixture.project) }
    #expect(try await fixture.git.run(["-C", fixture.linked.path, "rev-parse", "HEAD"]) == head)
    #expect(try await fixture.git.run(["-C", fixture.linked.path, "status", "--porcelain"]).isEmpty)
    let file = fixture.linked.appendingPathComponent("tracked.txt")
    try "unsaved work\n".write(to: file, atomically: true, encoding: .utf8)
    await #expect(throws: GroveError.self) { try await WorktreeRepository().pull(fixture.worktree, project: fixture.project) }
    #expect(try String(contentsOf: file, encoding: .utf8) == "unsaved work\n")
    #expect(try await fixture.git.run(["-C", fixture.linked.path, "stash", "list"]).isEmpty)
}

@Test func operationsRejectMissingUpstreamDetachedAndWrongRepository() async throws {
    let fixture = try await WorktreeFixture.create()
    defer { fixture.cleanUp() }
    let repository = WorktreeRepository()
    await #expect(throws: GroveError.self) { try await repository.pull(fixture.worktree, project: fixture.project) }
    _ = try await fixture.git.run(["-C", fixture.linked.path, "switch", "--detach"])
    await #expect(throws: GroveError.self) { try await repository.pull(fixture.worktree, project: fixture.project) }
    let wrong = Project(name: "Wrong", gitDirectory: fixture.root.appendingPathComponent("other/.git").path)
    await #expect(throws: GroveError.self) { try await repository.changes(in: fixture.worktree, project: wrong) }
    await #expect(throws: GroveError.self) { try await repository.switchBranch("feature", in: fixture.worktree, project: wrong) }
    try FileManager.default.removeItem(at: fixture.linked)
    await #expect(throws: GroveError.self) { try await repository.changes(in: fixture.worktree, project: fixture.project) }
}

@Test func diffSupportsUnbornRepositoriesAndLimitsLargePreviews() async throws {
    let fixture = try await WorktreeFixture.create()
    defer { fixture.cleanUp() }
    let unborn = fixture.root.appendingPathComponent("unborn")
    _ = try await fixture.git.run(["init", "-b", "main", unborn.path])
    try String(repeating: "a long added line\n", count: 20_000).write(to: unborn.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
    _ = try await fixture.git.run(["-C", unborn.path, "add", "."])
    let project = try await GitRepository().project(at: unborn)
    let tree = try #require(try await GitRepository().worktrees(in: project).first)
    let repository = WorktreeRepository()
    let changes = try await repository.changes(in: tree, project: project)
    let staged = try #require(changes.first { $0.section == .staged })
    let diff = try await repository.diff(for: staged, in: tree, project: project)
    #expect(diff.isTruncated)
    #expect(diff.text.utf8.count <= 200_000)
    #expect(diff.text.contains("+a long added line"))
    #expect(!changes.contains { $0.section == .unstaged })
}

@Test func diffDisablesExternalHelpersAndTextConversion() async throws {
    let fixture = try await WorktreeFixture.create()
    defer { fixture.cleanUp() }
    let marker = fixture.root.appendingPathComponent("helper-ran")
    let helper = fixture.root.appendingPathComponent("helper.sh")
    try "#!/bin/sh\ntouch '\(marker.path)'\nprintf converted\n".write(to: helper, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
    try "tracked.txt diff=custom\n".write(to: fixture.linked.appendingPathComponent(".gitattributes"), atomically: true, encoding: .utf8)
    for key in ["diff.custom.command", "diff.custom.textconv"] {
        _ = try await fixture.git.run(["-C", fixture.linked.path, "config", key, helper.path])
    }
    try "changed text\n".write(to: fixture.linked.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
    let repository = WorktreeRepository()
    let changes = try await repository.changes(in: fixture.worktree, project: fixture.project)
    let change = try #require(changes.first { $0.path == "tracked.txt" })
    let diff = try await repository.diff(for: change, in: fixture.worktree, project: fixture.project)
    #expect(diff.text.contains("+changed text"))
    #expect(!FileManager.default.fileExists(atPath: marker.path))
}

@Test func untrackedListIncludesEveryFileAndPreviewDoesNotFollowSymbolicLinks() async throws {
    let fixture = try await WorktreeFixture.create()
    defer { fixture.cleanUp() }
    let outside = fixture.root.appendingPathComponent("outside.txt")
    try "Do not preview a symlink target's contents\n".write(to: outside, atomically: true, encoding: .utf8)
    try FileManager.default.createSymbolicLink(at: fixture.linked.appendingPathComponent("00-link"), withDestinationURL: outside)
    for index in 1...50 {
        try "new file \(index)\n".write(to: fixture.linked.appendingPathComponent(String(format: "%02d.txt", index)),
                                      atomically: true, encoding: .utf8)
    }
    let repository = WorktreeRepository()
    let changes = try await repository.changes(in: fixture.worktree, project: fixture.project)
    #expect(changes.count == 51)
    let symlink = try #require(changes.first { $0.path == "00-link" })
    let diff = try await repository.diff(for: symlink, in: fixture.worktree, project: fixture.project)
    #expect(!diff.isTruncated)
    #expect(diff.text.contains("120000"))
    #expect(!diff.text.contains("Do not preview a symlink target's contents"))
    let last = try #require(changes.first { $0.path == "50.txt" })
    #expect(try await repository.diff(for: last, in: fixture.worktree, project: fixture.project).text.contains("+new file 50"))
}

@Test func fileDiffHandlesRenamesAndLiteralPathspecs() async throws {
    let fixture = try await WorktreeFixture.create()
    defer { fixture.cleanUp() }
    let path = fixture.linked.path
    let repository = WorktreeRepository()
    _ = try await fixture.git.run(["-C", path, "mv", "tracked.txt", "renamed\nfile.txt"])
    try "original\nnew edit\n".write(to: fixture.linked.appendingPathComponent("renamed\nfile.txt"), atomically: true, encoding: .utf8)
    let changes = try await repository.changes(in: fixture.worktree, project: fixture.project)
    let rename = try #require(changes.first { $0.section == .staged })
    let edit = try #require(changes.first { $0.section == .unstaged })
    #expect(rename.status == "R")
    #expect(rename.path == "renamed\nfile.txt")
    #expect(rename.originalPath == "tracked.txt")
    #expect(edit.originalPath == nil)
    #expect(try await repository.diff(for: rename, in: fixture.worktree, project: fixture.project).text.contains("rename from tracked.txt"))
    #expect(try await repository.diff(for: edit, in: fixture.worktree, project: fixture.project).text.contains("+new edit"))

    for name in ["*.txt", "other.txt", ":(glob)*.txt"] {
        try "original\n".write(to: fixture.linked.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
    _ = try await fixture.git.run(["-C", path, "add", "."])
    _ = try await fixture.git.run(["-C", path, "commit", "-m", "Add unusual filenames"])
    for name in ["*.txt", "other.txt", ":(glob)*.txt"] {
        try "edit to \(name)\n".write(to: fixture.linked.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
    let edits = try await repository.changes(in: fixture.worktree, project: fixture.project)
    for name in ["*.txt", ":(glob)*.txt"] {
        let change = try #require(edits.first { $0.path == name })
        let diff = try await repository.diff(for: change, in: fixture.worktree, project: fixture.project)
        #expect(diff.text.contains("+edit to \(name)"))
        #expect(!diff.text.contains("edit to other.txt"))
    }
}

@Test func conflictsAppearOnceInTheirOwnGroup() async throws {
    let fixture = try await WorktreeFixture.create()
    defer { fixture.cleanUp() }
    for (folder, value) in [(fixture.main, "main edit\n"), (fixture.linked, "feature edit\n")] {
        try value.write(to: folder.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        _ = try await fixture.git.run(["-C", folder.path, "commit", "-am", "Conflicting change"])
    }
    _ = try await fixture.git.run(["-C", fixture.linked.path, "merge", "--no-edit", "main"], acceptedExitCodes: [1])
    let repository = WorktreeRepository()
    let changes = try await repository.changes(in: fixture.worktree, project: fixture.project)
    #expect(changes.count == 1)
    let conflict = try #require(changes.first)
    #expect(conflict.section == .conflicted)
    #expect(conflict.path == "tracked.txt")
    #expect(try await repository.diff(for: conflict, in: fixture.worktree, project: fixture.project).text.contains("<<<<<<< HEAD"))
}
