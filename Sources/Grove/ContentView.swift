import AppKit
import GroveCore
import SwiftUI

struct ContentView: View {
    @Bindable var model: WorkspaceModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "tree.fill").font(.title).foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Grove").font(.title2.weight(.semibold))
                        Text("A home for your worktrees").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(20)
                List(selection: $model.selection) {
                    Section("Projects") {
                        ForEach(model.projects) { project in
                            Label(project.name, systemImage: "folder")
                                .lineLimit(1)
                                .help(project.gitDirectory)
                                .tag(project.id)
                                .contextMenu {
                                    Button("Remove from Grove", role: .destructive) { model.remove(project) }
                                }
                        }
                    }
                }
                .listStyle(.sidebar)
                Divider()
                Button(action: model.chooseProject) {
                    Label(model.isAdding ? "Adding Project…" : "Add Project…", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(16)
                .disabled(model.isAdding || !model.storageReady)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 320)
        } detail: {
            detail
                .navigationTitle(model.selectedProject?.name ?? "Grove")
                .toolbar {
                    if model.selectedProject != nil {
                        Button(action: model.refresh) { Label("Refresh", systemImage: "arrow.clockwise") }
                            .help("Refresh Worktrees (⌘R)")
                    }
                }
        }
        .onAppear { model.refresh() }
        .onChange(of: model.selection) { model.refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.refresh() } }
        .alert("Grove", isPresented: Binding(
            get: { model.actionError != nil }, set: { if !$0 { model.actionError = nil } }
        )) { Button("OK") { model.actionError = nil } } message: {
            Text(model.actionError ?? "")
        }
    }

    @ViewBuilder private var detail: some View {
        if let error = model.storageError {
            ContentUnavailableView {
                Label("Saved projects unavailable", systemImage: "exclamationmark.triangle")
            } description: { Text(error).textSelection(.enabled) } actions: {
                Button("Retry") { model.reloadProjects() }
            }
        } else if let project = model.selectedProject {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Worktrees").font(.largeTitle.weight(.semibold))
                        Text("Every working tree, together.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.updatedAt != nil {
                        Text("\(model.worktrees.count)")
                            .font(.title2.monospacedDigit()).foregroundStyle(.secondary)
                            .padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(24)
                Divider()
                if model.isLoading {
                    ProgressView("Reading worktrees…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = model.loadError {
                    ContentUnavailableView {
                        Label("Couldn’t read this project", systemImage: "exclamationmark.folder")
                    } description: {
                        Text(error).textSelection(.enabled)
                    } actions: { Button("Retry", action: model.refresh) }
                } else if model.worktrees.isEmpty {
                    ContentUnavailableView("No registered worktrees", systemImage: "tree", description: Text("Refresh to read the latest state from Git."))
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(Array(model.worktrees.enumerated()), id: \.element.id) { index, worktree in
                                WorktreeRow(worktree: worktree, isMain: index == 0)
                            }
                        }
                        .padding(24)
                    }
                }
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "internaldrive")
                    Text(project.gitDirectory).lineLimit(1).truncationMode(.middle).help(project.gitDirectory)
                    Spacer(minLength: 12)
                    if let date = model.updatedAt {
                        Text("Updated \(date.formatted(date: .omitted, time: .shortened))")
                    }
                }
                .font(.caption).foregroundStyle(.secondary).padding(12)
            }
        } else {
            ContentUnavailableView {
                Label("Your worktrees, in one place", systemImage: "tree")
            } description: {
                Text("Add a Git project to discover all its worktrees,\nwherever they were created.")
            } actions: {
                Button("Add Project…", action: model.chooseProject)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isAdding || !model.storageReady)
            }
        }
    }
}

private struct WorktreeRow: View {
    let worktree: Worktree
    let isMain: Bool
    private var exists: Bool { FileManager.default.fileExists(atPath: worktree.path) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isMain ? "house" : "arrow.triangle.branch")
                    .font(.title3).foregroundStyle(.green)
                    .frame(width: 36, height: 36)
                    .background(.green.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(worktree.name).font(.headline).textSelection(.enabled)
                        if isMain && !worktree.isBare { badge("Main") }
                        if worktree.isBare { badge("Bare") }
                    }
                    Label(worktree.revision, systemImage: worktree.isDetached ? "circle.dotted" : "arrow.triangle.branch")
                        .font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
                Menu {
                    Button("Copy Path") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(worktree.path, forType: .string)
                    }
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: worktree.path)])
                    }.disabled(!exists)
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).fixedSize()
                    .accessibilityLabel("Actions for \(worktree.name)")
            }
            Text(worktree.path).font(.caption).foregroundStyle(.secondary)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            if worktree.isDetached || worktree.lockReason != nil || worktree.pruneReason != nil || !exists {
                HStack(spacing: 8) {
                    if worktree.isDetached { badge("Detached HEAD") }
                    if let reason = worktree.lockReason { badge("Locked").help(reason.isEmpty ? "Locked by Git" : reason) }
                    if let reason = worktree.pruneReason { badge("Prunable").help(reason) }
                    if !exists { badge("Path unavailable") }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
    }

    private func badge(_ text: String) -> some View {
        Text(text).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
    }
}
