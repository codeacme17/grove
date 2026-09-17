import GroveCore
import Observation

@MainActor @Observable
final class WorktreeChangesModel {
    private(set) var changes: [WorktreeChange]?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    var collapsedSections: Set<ChangeSection> = []
    private var requestID = 0

    var changedFileCount: Int? {
        changes.map { Set($0.map(\.path)).count }
    }

    func observe(in worktree: Worktree, project: Project, onRefresh: @MainActor () async -> Void) async {
        let monitor = FileChangeMonitor(paths: [worktree.path, project.gitDirectory])
        defer { monitor.stop() }
        for await _ in monitor.events {
            guard !Task.isCancelled else { return }
            await load(in: worktree, project: project)
            guard !Task.isCancelled else { return }
            if errorMessage == nil { await onRefresh() }
        }
    }

    func load(in worktree: Worktree, project: Project) async {
        requestID += 1
        let request = requestID
        isLoading = true
        errorMessage = nil
        defer { if request == requestID { isLoading = false } }
        do {
            let result = try await WorktreeRepository().changes(in: worktree, project: project)
            guard request == requestID, !Task.isCancelled else { return }
            if changes != result { changes = result }
        } catch {
            guard request == requestID, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }
}
