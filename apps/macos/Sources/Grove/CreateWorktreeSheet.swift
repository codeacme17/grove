import AppKit
import GroveCore
import SwiftUI

struct CreateWorktreeSheet: View {
    let project: Project
    let model: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @State private var options: WorktreeCreationOptions?
    @State private var usesNewBranch = true
    @State private var name = ""
    @State private var selectedBranch = ""
    @State private var destination = ""
    @State private var customDestination = false
    @State private var isLoading = true
    @State private var isCreating = false
    @State private var isCancelling = false
    @State private var errorMessage: String?
    @State private var reloadID = 0
    @State private var operation: Task<Void, Never>?

    private var canCreate: Bool {
        guard let options, !isLoading, !isCreating, !model.isPerformingGitOperation,
              destination.hasPrefix("/"), let branch = options.branches.first(where: { $0.name == selectedBranch }) else { return false }
        return usesNewBranch ? !name.isEmpty : branch.checkedOutPath == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Worktree").font(.headline)
            Text(project.name).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 14) {
                Picker("Branch", selection: $usesNewBranch) {
                    Text("New Branch").tag(true)
                    Text("Existing Branch").tag(false)
                }
                .pickerStyle(.segmented)
                if usesNewBranch { TextField("New branch name", text: $name) }
                Picker(usesNewBranch ? "Start from" : "Local branch", selection: $selectedBranch) {
                    Text("Choose a local branch").tag("")
                    ForEach(options?.branches ?? []) { branch in
                        Text(!usesNewBranch && branch.checkedOutPath != nil ? "\(branch.name) — in use: \(branch.checkedOutPath!)" : branch.name)
                            .tag(branch.name)
                            .disabled(!usesNewBranch && branch.checkedOutPath != nil)
                    }
                }
                if options?.branches.isEmpty == true {
                    Text("No local branches with commits are available. Create an initial commit outside Grove first.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Text("Destination").font(.subheadline)
                TextField("Absolute path to a new directory", text: Binding(
                    get: { destination }, set: { destination = $0; customDestination = true }
                ))
                .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Choose Parent Folder…", action: chooseParent)
                    Button("Use Suggested Path") { customDestination = false; updateSuggestion() }
                }
                Text("The destination must not exist. Grove creates the directory and keeps the branch local.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .disabled(isLoading || isCreating)
            if let errorMessage {
                ScrollView { Text(errorMessage).foregroundStyle(.red).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 130)
            }
            HStack {
                Button("Reload") { reloadID += 1 }.disabled(isLoading || isCreating)
                LoadingIndicator(isLoading: isLoading, label: "Loading local branches")
                Spacer()
                LoadingIndicator(isLoading: isCreating, label: isCancelling ? "Stopping…" : "Creating worktree…")
                Button(isCreating ? "Stop" : "Cancel") {
                    if isCreating { isCancelling = true; operation?.cancel() } else { dismiss() }
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isCancelling)
                Button("Create", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
            }
        }
        .padding(24)
        .frame(width: 550)
        .interactiveDismissDisabled(isCreating)
        .onChange(of: name) { updateSuggestion() }
        .onChange(of: selectedBranch) { updateSuggestion() }
        .onChange(of: usesNewBranch) {
            selectedBranch = usesNewBranch ? options?.defaultBaseBranch ?? "" : ""
            updateSuggestion()
        }
        .task(id: reloadID) {
            isLoading = true
            errorMessage = nil
            do {
                let result = try await WorktreeRepository().creationOptions(project: project)
                try Task.checkCancellation()
                let firstLoad = options == nil
                options = result
                if firstLoad && usesNewBranch { selectedBranch = result.defaultBaseBranch ?? "" }
                if !result.branches.contains(where: { $0.name == selectedBranch && (usesNewBranch || $0.checkedOutPath == nil) }) {
                    selectedBranch = ""
                }
                updateSuggestion()
            } catch {
                guard !Task.isCancelled else { return }
                options = nil
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func updateSuggestion() {
        guard !customDestination, let options else { return }
        destination = options.suggestedDestination(for: usesNewBranch ? name : selectedBranch)
    }

    private func chooseParent() {
        let panel = NSOpenPanel()
        panel.title = "Choose the parent folder for the new worktree"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let parent = panel.url else { return }
            let suggested = options?.suggestedDestination(for: usesNewBranch ? name : selectedBranch) ?? "/new-worktree"
            destination = parent.appendingPathComponent(URL(fileURLWithPath: suggested).lastPathComponent).path
            customDestination = true
        }
    }

    private func create() {
        let branch: WorktreeBranch = usesNewBranch ? .new(name: name, base: selectedBranch) : .existing(name: selectedBranch)
        let path = destination
        isCreating = true
        errorMessage = nil
        operation = Task {
            do {
                _ = try await model.createWorktree(branch: branch, destination: path, project: project)
                dismiss()
            } catch {
                errorMessage = error is CancellationError ? "Creation stopped. The project has been refreshed; check for any remaining branch or directory before retrying." : error.localizedDescription
            }
            isCreating = false
            isCancelling = false
            operation = nil
        }
    }
}
