import GroveCore
import SwiftUI

struct BranchSwitchTarget: Identifiable {
    let worktree: Worktree
    let project: Project
    var id: String { worktree.path }
}

struct SwitchBranchSheet: View {
    let target: BranchSwitchTarget
    let model: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @State private var branches: [LocalBranch] = []
    @State private var selectedBranch = ""
    @State private var isLoading = true
    @State private var isSwitching = false
    @State private var errorMessage: String?
    @State private var reloadID = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Switch Branch").font(.headline)
            Text(target.worktree.name).foregroundStyle(.secondary)
            if branches.isEmpty && !isLoading {
                Text("No local branches available.").foregroundStyle(.secondary)
            } else {
                Picker("Local branch", selection: $selectedBranch) {
                    Text("Choose a branch").tag("")
                    ForEach(branches) { branch in
                        Text(label(for: branch)).tag(branch.name)
                            .disabled(branch.checkedOutPath != nil && branch.checkedOutPath != target.worktree.path)
                    }
                }
                .disabled(isSwitching || isLoading)
            }
            if let errorMessage {
                Text(errorMessage).font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }
            HStack {
                Button { reloadID += 1 } label: {
                    HStack(spacing: 4) {
                        Text("Reload")
                        LoadingIndicator(isLoading: isLoading, label: "Loading local branches", idleIcon: "arrow.clockwise")
                    }
                }
                .disabled(isLoading || isSwitching)
                Spacer()
                LoadingIndicator(isLoading: isSwitching, label: "Switching branch…")
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSwitching)
                Button("Switch") {
                    isSwitching = true
                    errorMessage = nil
                    Task {
                        do {
                            try await model.switchBranch(selectedBranch, in: target.worktree, project: target.project)
                            dismiss()
                        } catch { errorMessage = error.localizedDescription }
                        isSwitching = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isLoading || isSwitching || model.busyWorktreePath != nil || selectedBranch.isEmpty
                          || target.worktree.branch == "refs/heads/\(selectedBranch)")
            }
        }
        .padding(24)
        .frame(width: 420)
        .interactiveDismissDisabled(isSwitching)
        .task(id: reloadID) {
            isLoading = true
            errorMessage = nil
            do {
                let result = try await WorktreeRepository().branches(in: target.worktree, project: target.project)
                try Task.checkCancellation()
                branches = result
                if !result.contains(where: { $0.name == selectedBranch && $0.checkedOutPath == nil }) {
                    selectedBranch = ""
                }
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func label(for branch: LocalBranch) -> String {
        if target.worktree.branch == "refs/heads/\(branch.name)" { return "\(branch.name) (current)" }
        if let path = branch.checkedOutPath { return "\(branch.name) — in use: \(path)" }
        return branch.name
    }
}
