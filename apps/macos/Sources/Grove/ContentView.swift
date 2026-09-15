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
    @State private var switchingWorktree: BranchSwitchTarget?
    @State private var expandedDiffs: Set<String> = []
    @State private var diffSelection: FileDiffSelection?
    @State private var diffRevision = 0
    @GestureState private var sidebarDrag: CGFloat = 0
    @GestureState private var isResizingSidebar = false

    private var currentSidebarWidth: CGFloat { min(320, max(220, sidebarWidth + sidebarDrag)) }

    var body: some View {
        GeometryReader { geometry in
            let showsSidebar = isSidebarVisible && (diffSelection == nil || geometry.size.width >= currentSidebarWidth + 706)
            HStack(spacing: 0) {
                HStack(spacing: 0) {
                    sidebar
                        .frame(width: currentSidebarWidth)
                    sidebarResizeHandle
                }
                .frame(width: showsSidebar ? currentSidebarWidth + 6 : 0, alignment: .trailing)
                .clipped()
                .allowsHitTesting(showsSidebar)
                .disabled(!showsSidebar)
                .accessibilityHidden(!showsSidebar)
                DiffWorkspaceSplit(isPresented: diffSelection != nil) {
                    detail
                } panel: {
                    if let diffSelection {
                        FileDiffPanel(selection: diffSelection,
                                      isBusy: model.busyWorktreePath != nil || model.isLoading,
                                      refreshedAt: model.updatedAt, revision: diffRevision) {
                            self.diffSelection = nil
                        }
                    }
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: showsSidebar)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: diffSelection != nil)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        if !showsSidebar && diffSelection != nil && geometry.size.width < currentSidebarWidth + 706 {
                            diffSelection = nil
                            isSidebarVisible = true
                        } else {
                            isSidebarVisible.toggle()
                        }
                    } label: {
                        Label("Toggle Sidebar", systemImage: "sidebar.left")
                    }
                    .help(showsSidebar ? "Hide Sidebar" : "Show Sidebar")
                    .keyboardShortcut("s", modifiers: [.command, .control])
                }
                ToolbarItem {
                    if model.selectedProject != nil {
                        Button(action: model.refresh) { Label("Refresh", systemImage: "arrow.clockwise") }
                            .help("Refresh Worktrees (⌘R)")
                    }
                }
            }
        }
        .background(colorScheme == .light ? GroveBrand.lightBackground : Color(nsColor: .windowBackgroundColor))
        .toolbarBackground(colorScheme == .light ? AnyShapeStyle(GroveBrand.lightBackground) : AnyShapeStyle(.bar), for: .windowToolbar)
        .toolbarBackground(colorScheme == .light ? .visible : .automatic, for: .windowToolbar)
        .navigationTitle(model.selectedProject?.name ?? "Grove")
        .onAppear { model.refresh() }
        .onChange(of: model.selection) {
            diffSelection = nil
            model.refresh()
        }
        .onChange(of: model.updatedAt) { _, date in
            guard date != nil, let diffSelection else { return }
            if !model.worktrees.contains(where: { $0.path == diffSelection.worktree.path && !$0.isBare && $0.pruneReason == nil }) {
                self.diffSelection = nil
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.refresh() } }
        .sheet(item: $renamingProject) { project in
            RenameProjectSheet(project: project) { name in
                try model.rename(project, to: name)
            }
        }
        .sheet(item: $switchingWorktree) { target in
            SwitchBranchSheet(target: target, model: model)
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
                                WorktreeRow(worktree: worktree, project: project, isMain: index == 0,
                                            model: model, isDiffExpanded: Binding(
                                                get: { expandedDiffs.contains(worktree.path) },
                                                set: { expanded in
                                                    if expanded { expandedDiffs.insert(worktree.path) }
                                                    else { expandedDiffs.remove(worktree.path) }
                                                }
                                            ), selectedChange: Binding(
                                                get: { diffSelection?.worktree.path == worktree.path ? diffSelection?.change : nil },
                                                set: { change in
                                                    if let change {
                                                        diffSelection = FileDiffSelection(change: change, worktree: worktree, project: project)
                                                    } else if diffSelection?.worktree.path == worktree.path {
                                                        diffSelection = nil
                                                    }
                                                }
                                            ), onDiffRefresh: { diffRevision += 1 }, onSwitchBranch: {
                                                switchingWorktree = BranchSwitchTarget(worktree: worktree, project: project)
                                            })
                            }
                        }
                        .padding(24)
                    }
                }
                HStack(spacing: 8) {
                    Image(systemName: "internaldrive")
                    Text(project.gitDirectory).lineLimit(1).truncationMode(.middle).help(project.gitDirectory)
                    Spacer(minLength: 12)
                    if model.updatedAt != nil {
                        Text("\(model.worktrees.count) \(model.worktrees.count == 1 ? "worktree" : "worktrees")")
                            .monospacedDigit()
                            .fixedSize()
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
