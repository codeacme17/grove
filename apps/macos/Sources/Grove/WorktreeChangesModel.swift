import GroveCore
import Observation

@MainActor @Observable
final class WorktreeChangesModel {
    private(set) var changes: [WorktreeChange]?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    var collapsedSections: Set<ChangeSection> = []
    private var requestID = 0

    func load(in worktree: Worktree, project: Project) async {
        requestID += 1
        let request = requestID
        isLoading = true
        errorMessage = nil
        defer { if request == requestID { isLoading = false } }
        do {
            let result = try await WorktreeRepository().changes(in: worktree, project: project)
            guard request == requestID, !Task.isCancelled else { return }
            changes = result
        } catch {
            guard request == requestID, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }
}
