import AppKit
import GroveCore
import Observation
import SwiftUI

@MainActor @Observable
final class WorkspaceModel {
    private(set) var projects: [Project] = []
    var selection: String?
    private(set) var worktrees: [Worktree] = []
    private(set) var isLoading = false
    private(set) var isAdding = false
    private(set) var storageReady = false
    private(set) var storageError: String?
    private(set) var loadError: String?
    private(set) var updatedAt: Date?
    var actionError: String?
    private(set) var busyWorktreePath: String?
    private(set) var worktreeMessages: [String: String] = [:]
    @ObservationIgnored private let repository = GitRepository()
    @ObservationIgnored private let store: ProjectStore
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    var selectedProject: Project? { projects.first { $0.id == selection } }

    init(store: ProjectStore = ProjectStore()) {
        self.store = store
        reloadProjects()
    }

    func reloadProjects() {
        do {
            projects = try store.load()
            selection = projects.first?.id
            storageReady = true
            storageError = nil
        } catch {
            storageReady = false
            storageError = "Could not read saved projects. Your saved file has been preserved.\n\(error.localizedDescription)"
        }
    }

    func chooseProject() {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible) else { return }
        chooseProject(in: window)
    }

    func chooseProject(in window: NSWindow) {
        guard storageReady, !isAdding else { return }
        let panel = NSOpenPanel()
        panel.title = "Add a Git project"
        panel.message = "Choose a repository or any of its worktrees."
        panel.prompt = "Add Project"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        isAdding = true
        panel.beginSheetModal(for: window) { response in
            Task { @MainActor in
                defer { self.isAdding = false }
                guard response == .OK, let url = panel.url else { return }
                do {
                    let project = try await self.repository.project(at: url)
                    if !self.projects.contains(where: { $0.id == project.id }) {
                        let next = self.projects + [project]
                        try self.store.save(next)
                        self.projects = next
                    }
                    self.selection = project.id
                    self.refresh()
                } catch {
                    self.actionError = "Could not add this project. Choose a local Git repository.\n\(error.localizedDescription)"
                }
            }
        }
    }

    func remove(_ project: Project) {
        guard storageReady else { return }
        do {
            let next = projects.filter { $0.id != project.id }
            try store.save(next)
            projects = next
            if selection == project.id { selection = next.first?.id }
        } catch { actionError = "Could not save the project list.\n\(error.localizedDescription)" }
    }

    func moveProjects(from offsets: IndexSet, to destination: Int) {
        guard storageReady else { return }
        var next = projects
        next.move(fromOffsets: offsets, toOffset: destination)
        do {
            try store.save(next)
            projects = next
        } catch { actionError = "Could not save the project order.\n\(error.localizedDescription)" }
    }

    func rename(_ project: Project, to name: String) throws {
        guard storageReady else {
            throw GroveError.message("Saved projects are unavailable. Retry loading them first.")
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw GroveError.message("Enter a project name.")
        }
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else {
            throw GroveError.message("This project is no longer in Grove.")
        }
        var next = projects
        next[index] = Project(name: trimmedName, gitDirectory: project.gitDirectory)
        try store.save(next)
        projects = next
    }

    func pull(_ worktree: Worktree, project: Project) async throws {
        try await performWorktreeOperation(worktree, project: project) {
            _ = try await WorktreeRepository().pull(worktree, project: project)
            return "Pull completed."
        }
    }

    func switchBranch(_ name: String, in worktree: Worktree, project: Project) async throws {
        try await performWorktreeOperation(worktree, project: project) {
            try await WorktreeRepository().switchBranch(name, in: worktree, project: project)
            return "Switched to \(name)."
        }
    }

    private func performWorktreeOperation(_ worktree: Worktree, project: Project,
                                          action: () async throws -> String) async throws {
        guard busyWorktreePath == nil else {
            throw GroveError.message("Wait for the current Git operation to finish.")
        }
        busyWorktreePath = worktree.path
        worktreeMessages[worktree.path] = nil
        defer {
            busyWorktreePath = nil
            if selectedProject?.id == project.id { refresh() }
        }
        worktreeMessages[worktree.path] = try await action()
    }

    func refresh() {
        refreshTask?.cancel()
        worktrees = []
        updatedAt = nil
        loadError = nil
        isLoading = false
        guard let project = selectedProject else { return }
        isLoading = true
        refreshTask = Task {
            do {
                let result = try await repository.worktrees(in: project)
                guard !Task.isCancelled else { return }
                worktrees = result
                updatedAt = Date()
                isLoading = false
            } catch {
                guard !Task.isCancelled else { return }
                loadError = error.localizedDescription
                isLoading = false
            }
        }
    }
}
