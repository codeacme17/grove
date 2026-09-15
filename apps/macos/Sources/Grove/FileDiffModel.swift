import GroveCore
import Observation

@MainActor @Observable
final class FileDiffModel {
    struct Snapshot {
        let selection: FileDiffSelection
        let content: DiffContent
    }

    private(set) var snapshot: Snapshot?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private var requestID = 0
    private let read: @Sendable (FileDiffSelection) async throws -> DiffContent

    init(read: @escaping @Sendable (FileDiffSelection) async throws -> DiffContent = { selection in
        try await WorktreeRepository().diff(for: selection.change, in: selection.worktree, project: selection.project)
    }) {
        self.read = read
    }

    func load(_ selection: FileDiffSelection) async {
        requestID += 1
        let request = requestID
        isLoading = true
        errorMessage = nil
        defer { if requestID == request { isLoading = false } }
        do {
            let content = try await read(selection)
            guard requestID == request, !Task.isCancelled else { return }
            snapshot = Snapshot(selection: selection, content: content)
        } catch {
            guard requestID == request, !Task.isCancelled else { return }
            errorMessage = "Couldn’t load \(selection.change.path): \(error.localizedDescription)"
        }
    }
}
