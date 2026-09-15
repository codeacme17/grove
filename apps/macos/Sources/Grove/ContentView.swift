import AppKit
import GroveCore
import SwiftUI

struct ContentView: View {
    @Bindable var model: WorkspaceModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSidebarVisible = true
    @State private var sidebarWidth: CGFloat = 240
    @State private var isHoveringSidebarHandle = false
    @State private var renamingProject: Project?
    @GestureState private var sidebarDrag: CGFloat = 0
    @GestureState private var isResizingSidebar = false

    private var currentSidebarWidth: CGFloat { min(320, max(220, sidebarWidth + sidebarDrag)) }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar
                    .frame(width: currentSidebarWidth)
                sidebarResizeHandle
            }
            .frame(width: isSidebarVisible ? currentSidebarWidth + 6 : 0, alignment: .trailing)
            .clipped()
            .allowsHitTesting(isSidebarVisible)
            .disabled(!isSidebarVisible)
            .accessibilityHidden(!isSidebarVisible)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: isSidebarVisible)
        .background(colorScheme == .light ? GroveBrand.lightBackground : Color(nsColor: .windowBackgroundColor))
        .toolbarBackground(colorScheme == .light ? AnyShapeStyle(GroveBrand.lightBackground) : AnyShapeStyle(.bar), for: .windowToolbar)
        .toolbarBackground(colorScheme == .light ? .visible : .automatic, for: .windowToolbar)
        .navigationTitle(model.selectedProject?.name ?? "Grove")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    isSidebarVisible.toggle()
                } label: {
                    Label("Toggle Sidebar", systemImage: "sidebar.left")
                }
                .help(isSidebarVisible ? "Hide Sidebar" : "Show Sidebar")
                .keyboardShortcut("s", modifiers: [.command, .control])
            }
            ToolbarItem {
                if model.selectedProject != nil {
                    Button(action: model.refresh) { Label("Refresh", systemImage: "arrow.clockwise") }
                        .help("Refresh Worktrees (⌘R)")
                }
            }
        }
        .onAppear { model.refresh() }
        .onChange(of: model.selection) { model.refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.refresh() } }
        .sheet(item: $renamingProject) { project in
            RenameProjectSheet(project: project) { name in
                try model.rename(project, to: name)
            }
        }
        .alert("Grove", isPresented: Binding(
            get: { model.actionError != nil }, set: { if !$0 { model.actionError = nil } }
        )) { Button("OK") { model.actionError = nil } } message: {
            Text(model.actionError ?? "")
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                GroveLogo(size: 56)
                Text("Grove")
                    .font(.system(size: 21, weight: .medium, design: .rounded))
                    .tracking(-0.3)
                    .fixedSize()
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
                                Button("Rename…") { renamingProject = project }
                                Button("Remove from Grove", role: .destructive) { model.remove(project) }
                            }
                    }
                    .onMove(perform: model.moveProjects)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            Button(action: model.chooseProject) {
                Label(model.isAdding ? "Adding Project…" : "Add Project…", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(16)
            .disabled(model.isAdding || !model.storageReady)
        }
    }

    private var sidebarResizeHandle: some View {
        Color.clear
            .frame(width: 6)
            .overlay {
                Rectangle()
                    .fill(.secondary.opacity(0.35))
                    .frame(width: 1)
                    .opacity(isHoveringSidebarHandle || isResizingSidebar ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.12),
                               value: isHoveringSidebarHandle || isResizingSidebar)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                isHoveringSidebarHandle = hovering
                if hovering { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() }
            }
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .updating($sidebarDrag) { value, state, _ in state = value.translation.width }
                    .updating($isResizingSidebar) { _, state, _ in state = true }
                    .onEnded { value in
                        sidebarWidth = min(320, max(220, sidebarWidth + value.translation.width))
                    }
            )
            .accessibilityLabel("Sidebar width")
            .accessibilityValue("\(Int(sidebarWidth)) points")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: sidebarWidth = min(320, sidebarWidth + 20)
                case .decrement: sidebarWidth = max(220, sidebarWidth - 20)
                @unknown default: break
                }
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
                if model.isLoading {
                    ProgressView("Reading worktrees…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = model.loadError {
                    ContentUnavailableView {
                        Label("Couldn’t read this project", systemImage: "exclamationmark.folder")
                    } description: {
                        Text(error).textSelection(.enabled)
                    } actions: { Button("Retry", action: model.refresh) }
                } else if model.worktrees.isEmpty {
                    ContentUnavailableView {
                        GroveEmptyStateLabel(title: "No registered worktrees")
                    } description: { Text("Refresh to read the latest state from Git.") }
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
                HStack(spacing: 8) {
                    Image(systemName: "internaldrive")
                    Text(project.gitDirectory).lineLimit(1).truncationMode(.middle).help(project.gitDirectory)
                    Spacer(minLength: 12)
                    if let date = model.updatedAt {
                        Text("\(model.worktrees.count) \(model.worktrees.count == 1 ? "worktree" : "worktrees")")
                            .monospacedDigit()
                            .fixedSize()
                        Text("·")
                        Text("Updated \(date.formatted(date: .omitted, time: .shortened))")
                    }
                }
                .font(.caption).foregroundStyle(.secondary).padding(12)
            }
        } else {
            ContentUnavailableView {
                GroveEmptyStateLabel(title: "Your worktrees, in one place")
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
    @Environment(\.colorScheme) private var colorScheme
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
        .background(colorScheme == .light ? AnyShapeStyle(GroveBrand.lightBackground) : AnyShapeStyle(.background),
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
    }

    private func badge(_ text: String) -> some View {
        Text(text).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
    }
}
