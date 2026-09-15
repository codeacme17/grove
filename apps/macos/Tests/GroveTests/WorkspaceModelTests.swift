import Foundation
import GroveCore
import Testing
@testable import Grove

private struct WorkspaceFixture {
    let root: URL
    let file: URL
    let store: ProjectStore
    let projects: [Project]

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("grove-workspace-\(UUID().uuidString)")
        file = root.appendingPathComponent("settings/projects.json")
        store = ProjectStore(file: file)
        projects = ["Alpha", "Beta", "Gamma"].map { [root] in
            Project(name: $0, gitDirectory: root.appendingPathComponent("\($0)/.git").path)
        }
        try store.save(projects)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }

    func blockSaving() throws {
        let directory = file.deletingLastPathComponent()
        try FileManager.default.removeItem(at: directory)
        try Data("Not a directory".utf8).write(to: directory)
    }
}

@MainActor @Test func movingProjectsPersistsBothDirectionsAndKeepsSelection() throws {
    let fixture = try WorkspaceFixture()
    defer { fixture.cleanUp() }
    let model = WorkspaceModel(store: fixture.store)
    model.selection = fixture.projects[1].id

    model.moveProjects(from: IndexSet(integer: 0), to: 3)
    #expect(model.projects.map(\.name) == ["Beta", "Gamma", "Alpha"])
    #expect(try fixture.store.load() == model.projects)
    #expect(model.selection == fixture.projects[1].id)

    model.moveProjects(from: IndexSet(integer: 2), to: 0)
    #expect(model.projects == fixture.projects)
    #expect(WorkspaceModel(store: fixture.store).projects == fixture.projects)
    #expect(model.selection == fixture.projects[1].id)
}

@MainActor @Test func renamingPersistsWithoutChangingIdentityOrOrder() throws {
    let fixture = try WorkspaceFixture()
    defer { fixture.cleanUp() }
    let model = WorkspaceModel(store: fixture.store)
    let project = fixture.projects[1]
    model.selection = project.id

    try model.rename(project, to: "  My Workspace \n")
    #expect(model.projects.map(\.id) == fixture.projects.map(\.id))
    #expect(model.selectedProject?.name == "My Workspace")
    #expect(model.selection == project.id)
    #expect(WorkspaceModel(store: fixture.store).projects[1].name == "My Workspace")
    #expect(model.projects[1].gitDirectory == project.gitDirectory)

    #expect(throws: GroveError.self) { try model.rename(project, to: " \n ") }
    #expect(model.projects[1].name == "My Workspace")
    #expect(try fixture.store.load() == model.projects)
}

@MainActor @Test func failedWritesPreserveProjectNamesOrderAndSelection() throws {
    let fixture = try WorkspaceFixture()
    defer { fixture.cleanUp() }
    let model = WorkspaceModel(store: fixture.store)
    let selection = model.selection
    try fixture.blockSaving()

    model.moveProjects(from: IndexSet(integer: 0), to: 3)
    #expect(model.actionError != nil)
    #expect(model.projects == fixture.projects)
    #expect(throws: (any Error).self) { try model.rename(fixture.projects[0], to: "Renamed") }
    #expect(model.projects == fixture.projects)
    model.remove(fixture.projects[0])
    #expect(model.projects == fixture.projects)
    #expect(model.selection == selection)
}

@MainActor @Test func removingAProjectKeepsItsFilesAndPersistsRemainingOrder() throws {
    let fixture = try WorkspaceFixture()
    defer { fixture.cleanUp() }
    let model = WorkspaceModel(store: fixture.store)
    let project = fixture.projects[0]
    let gitDirectory = URL(fileURLWithPath: project.gitDirectory)
    try FileManager.default.createDirectory(at: gitDirectory, withIntermediateDirectories: true)
    let marker = gitDirectory.appendingPathComponent("marker")
    try Data("Keep repository files".utf8).write(to: marker)

    model.remove(project)
    #expect(model.projects == Array(fixture.projects.dropFirst()))
    #expect(model.selection == fixture.projects[1].id)
    #expect(try fixture.store.load() == model.projects)
    #expect(try String(contentsOf: marker, encoding: .utf8) == "Keep repository files")
    #expect(throws: GroveError.self) { try model.rename(project, to: "Removed") }
    #expect(try fixture.store.load() == model.projects)
}

@MainActor @Test func refreshingTheSameProjectKeepsItsVisibleSnapshot() async throws {
    let fixture = try WorkspaceFixture()
    defer { fixture.cleanUp() }
    let folder = fixture.root.appendingPathComponent("repository")
    _ = try await GitRunner().run(["init", "-b", "main", folder.path])
    let project = try await GitRepository().project(at: folder)
    try fixture.store.save([project])
    let model = WorkspaceModel(store: fixture.store)
    model.refresh()
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while model.isLoading && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(model.loadError == nil)
    let timestamp = try #require(model.updatedAt)
    let snapshot = model.worktrees
    #expect(snapshot.count == 1)

    model.refresh()
    #expect(model.worktrees == snapshot)
    #expect(model.updatedAt == timestamp)
    #expect(model.isLoading)
    let nextDeadline = ContinuousClock.now.advanced(by: .seconds(5))
    while model.isLoading && ContinuousClock.now < nextDeadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(!model.isLoading)
    #expect(model.worktrees == snapshot)

    model.selection = nil
    model.refresh()
    #expect(model.worktrees.isEmpty)
    #expect(!model.hasWorktreeSnapshot)
}

@MainActor @Test func returningToAProjectImmediatelyRestoresItsSnapshot() async throws {
    let fixture = try WorkspaceFixture()
    defer { fixture.cleanUp() }
    var projects: [Project] = []
    for name in ["First", "Second"] {
        let folder = fixture.root.appendingPathComponent(name)
        _ = try await GitRunner().run(["init", "-b", "main", folder.path])
        projects.append(try await GitRepository().project(at: folder))
    }
    try fixture.store.save(projects)
    let model = WorkspaceModel(store: fixture.store)
    func waitForRefresh() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while model.isLoading && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(model.loadError == nil)
        #expect(!model.isLoading)
    }
    model.refresh()
    try await waitForRefresh()
    let first = model.worktrees
    model.selection = projects[1].id
    model.refresh()
    #expect(model.worktrees == first)
    #expect(model.displayedProject?.id == projects[0].id)
    #expect(model.isProjectTransitioning)
    try await waitForRefresh()
    #expect(model.worktrees != first)
    #expect(model.displayedProject?.id == projects[1].id)
    #expect(!model.isProjectTransitioning)
    model.selection = projects[0].id
    model.refresh()
    #expect(model.hasWorktreeSnapshot)
    #expect(model.worktrees == first)
    try await waitForRefresh()
}

@MainActor @Test func returningToAWorktreeReusesItsChangeListAndCollapsedGroups() async throws {
    let fixture = try WorkspaceFixture()
    defer { fixture.cleanUp() }
    let folder = fixture.root.appendingPathComponent("repository")
    _ = try await GitRunner().run(["init", "-b", "main", folder.path])
    try "new content".write(to: folder.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
    let project = try await GitRepository().project(at: folder)
    let worktree = try #require(try await GitRepository().worktrees(in: project).first)
    let model = WorkspaceModel(store: fixture.store)
    let list = model.changesModel(for: worktree, project: project)
    await list.load(in: worktree, project: project)
    list.collapsedSections.insert(.untracked)
    let restored = model.changesModel(for: worktree, project: project)
    #expect(restored === list)
    #expect(restored.changes?.first?.path == "new.txt")
    #expect(restored.collapsedSections.contains(.untracked))
}
