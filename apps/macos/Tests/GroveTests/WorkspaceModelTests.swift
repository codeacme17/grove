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
