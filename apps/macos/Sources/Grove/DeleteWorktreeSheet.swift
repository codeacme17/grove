import GroveCore
import SwiftUI

struct WorktreeRemovalTarget: Identifiable {
    let worktree: Worktree
    let project: Project
    var id: String { worktree.path }
}

struct DeleteWorktreeSheet: View {
    let target: WorktreeRemovalTarget
    let model: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @State private var isChecking = true
    @State private var isDeleting = false
    @State private var isCancelling = false
    @State private var isEligible = false
    @State private var errorMessage: String?
    @State private var reloadID = 0
    @State private var operation: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Delete Worktree?").font(.headline)
            Text(target.worktree.name).font(.title3)
            Text(target.worktree.path).font(.callout.monospaced()).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Text("This removes the directory and its Git worktree registration. The local branch and its commits will be kept.")
            if let errorMessage {
                ScrollView { Text(errorMessage).foregroundStyle(.red).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 150)
            }
            HStack {
                Button("Check Again") { reloadID += 1 }.disabled(isChecking || isDeleting)
                LoadingIndicator(isLoading: isChecking, label: "Checking deletion safety")
                Spacer()
                LoadingIndicator(isLoading: isDeleting, label: isCancelling ? "Stopping…" : "Deleting worktree…")
                Button(isDeleting ? "Stop" : "Cancel") {
                    if isDeleting { isCancelling = true; operation?.cancel() } else { dismiss() }
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isCancelling)
                Button("Delete Worktree", role: .destructive, action: remove)
                    .disabled(isChecking || isDeleting || !isEligible || model.isPerformingGitOperation)
            }
        }
        .padding(24)
        .frame(width: 550)
        .interactiveDismissDisabled(isDeleting)
        .task(id: reloadID) {
            isChecking = true
            isEligible = false
            errorMessage = nil
            do {
                try await WorktreeRepository().validateRemoval(target.worktree, project: target.project)
                try Task.checkCancellation()
                isEligible = true
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
            isChecking = false
        }
    }

    private func remove() {
        isDeleting = true
        errorMessage = nil
        operation = Task {
            do {
                try await model.removeWorktree(target.worktree, project: target.project)
                dismiss()
            } catch {
                errorMessage = error is CancellationError ? "Deletion stopped. The project has been refreshed; inspect its current state before retrying." : error.localizedDescription
                isEligible = false
            }
            isDeleting = false
            isCancelling = false
            operation = nil
        }
    }
}
