import AppKit
import GroveCore
import SwiftUI

struct ContentView: View {
    @Bindable var model: WorkspaceModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("projectNavigationPlacement") private var navigationPlacement: ProjectNavigationPlacement = .sidebar
    @State private var isSidebarVisible = true
    @State private var isTopTabBarVisible = true
    @State private var sidebarWidth: CGFloat = 240
    @State private var isHoveringSidebarHandle = false
    @State private var renamingProject: Project?
    @State private var switchingWorktree: BranchSwitchTarget?
    @State private var expandedDiffs: Set<String> = []
    @State private var diffSelection: FileDiffSelection?
    @State private var isDiffPanelVisible = false
    @State private var diffRevision = 0
    @State private var pathCopyNotificationID: UUID?
    @GestureState private var sidebarDrag: CGFloat = 0
    @GestureState private var isResizingSidebar = false

    private var currentSidebarWidth: CGFloat { min(320, max(220, sidebarWidth + sidebarDrag)) }

    var body: some View {
        GeometryReader { geometry in
            let showsSidebar = navigationPlacement == .sidebar && isSidebarVisible && (!isDiffPanelVisible || geometry.size.width >= currentSidebarWidth + 706)
            let showsTopTabBar = navigationPlacement == .top && isTopTabBarVisible
            VStack(spacing: 0) {
                ProjectTabBar(model: model, isVisible: showsTopTabBar, onRename: { renamingProject = $0 },
                              onSwitchToSidebar: { setNavigationPlacement(.sidebar, availableWidth: geometry.size.width) })
                    .frame(height: showsTopTabBar ? 48 : 0, alignment: .top)
                    .clipped()
                    .allowsHitTesting(showsTopTabBar)
                    .disabled(!showsTopTabBar)
                    .accessibilityHidden(!showsTopTabBar)
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
                    DiffWorkspaceSplit(isPresented: isDiffPanelVisible) {
                        detail
                            .transaction { $0.animation = nil }
                    } panel: {
                        if let diffSelection {
                            FileDiffPanel(selection: diffSelection, isActive: isDiffPanelVisible,
                                          isBusy: model.busyWorktreePath != nil || model.isLoading,
                                          refreshedAt: model.updatedAt, revision: diffRevision) {
                                isDiffPanelVisible = false
                            }
                            .id(diffSelection.project.id)
                        }
                    }
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: showsSidebar)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: showsTopTabBar)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: navigationPlacement)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        if navigationPlacement == .top {
                            isTopTabBarVisible.toggle()
                        } else if !showsSidebar && isDiffPanelVisible && geometry.size.width < currentSidebarWidth + 706 {
                            isDiffPanelVisible = false
                            isSidebarVisible = true
                        } else {
                            isSidebarVisible.toggle()
                        }
                    } label: {
                        Label(navigationPlacement == .top ? "Toggle Tab Bar" : "Toggle Sidebar",
                              systemImage: navigationPlacement == .top ? "rectangle.topthird.inset.filled" : "sidebar.left")
                    }
                    .help(navigationPlacement == .top ? (showsTopTabBar ? "Hide Tab Bar" : "Show Tab Bar") : (showsSidebar ? "Hide Sidebar" : "Show Sidebar"))
                    .keyboardShortcut("s", modifiers: [.command, .control])
                }
                ToolbarItem {
                    if model.selectedProject != nil {
                        Button(action: model.refresh) {
                            LoadingIndicator(isLoading: model.isLoading, label: "Refresh worktrees", idleIcon: "arrow.clockwise")
                        }
                        .disabled(model.isLoading)
                        .help("Refresh Worktrees (⌘R)")
                    }
                }
            }
        }
        .background(colorScheme == .light ? GroveBrand.lightBackground : Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            VStack {
                if pathCopyNotificationID != nil {
                    Label {
                        Text("Path copied")
                    } icon: {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.quaternary))
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                    .transition(.opacity)
                }
            }
            .padding(.bottom, 24)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: pathCopyNotificationID != nil)
            .allowsHitTesting(false)
        }
        .task(id: pathCopyNotificationID) {
            guard let notificationID = pathCopyNotificationID else { return }
            do { try await Task.sleep(for: .seconds(2)) }
            catch { return }
            guard pathCopyNotificationID == notificationID else { return }
            pathCopyNotificationID = nil
        }
        .toolbarBackground(colorScheme == .light ? AnyShapeStyle(GroveBrand.lightBackground) : AnyShapeStyle(.bar), for: .windowToolbar)
        .toolbarBackground(colorScheme == .light ? .visible : .automatic, for: .windowToolbar)
        .navigationTitle(model.displayedProject?.name ?? "Grove")
        .onAppear { model.refresh() }
        .onChange(of: model.selection) {
            isDiffPanelVisible = false
            model.refresh()
        }
        .onChange(of: model.updatedAt) { _, date in
            guard date != nil, isDiffPanelVisible, let diffSelection else { return }
            if !model.worktrees.contains(where: { $0.path == diffSelection.worktree.path && !$0.isBare && $0.pruneReason == nil }) {
                isDiffPanelVisible = false
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
                                Divider()
                                switchToTopButton
                            }
                    }
                    .onMove(perform: model.moveProjects)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .contextMenu { switchToTopButton }
            Button(action: model.chooseProject) {
                Label(model.isAdding ? "Adding Project…" : "Add Project…", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(16)
            .disabled(model.isAdding || !model.storageReady)
        }
        .contentShape(Rectangle())
        .contextMenu { switchToTopButton }
    }

    private var switchToTopButton: some View {
        Button("Switch to Top", systemImage: "rectangle.topthird.inset.filled") {
            setNavigationPlacement(.top)
        }
    }

    private func setNavigationPlacement(_ placement: ProjectNavigationPlacement, availableWidth: CGFloat? = nil) {
        navigationPlacement = placement
        if placement == .top {
            isTopTabBarVisible = true
        } else {
            isSidebarVisible = true
            if let availableWidth, availableWidth < currentSidebarWidth + 706 {
                isDiffPanelVisible = false
            }
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
        } else if let project = model.displayedProject {
            VStack(alignment: .leading, spacing: 0) {
                if model.hasWorktreeSnapshot, let error = model.loadError {
                    Text("Couldn’t load \(model.selectedProject?.name ?? project.name): \(error)").font(.caption).foregroundStyle(.red)
                        .textSelection(.enabled).padding(12)
                }
                if !model.hasWorktreeSnapshot, let error = model.loadError {
                    ContentUnavailableView {
                        Label("Couldn’t read this project", systemImage: "exclamationmark.folder")
                    } description: {
                        Text(error).textSelection(.enabled)
                    } actions: { Button("Retry", action: model.refresh) }
                } else if !model.hasWorktreeSnapshot {
                    Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
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
                                                get: { isDiffPanelVisible && diffSelection?.worktree.path == worktree.path ? diffSelection?.change : nil },
                                                set: { change in
                                                    if let change {
                                                        diffSelection = FileDiffSelection(change: change, worktree: worktree, project: project)
                                                        isDiffPanelVisible = true
                                                    } else if diffSelection?.worktree.path == worktree.path {
                                                        isDiffPanelVisible = false
                                                    }
                                                }
                                            ), onDiffRefresh: { diffRevision += 1 }, onSwitchBranch: {
                                                switchingWorktree = BranchSwitchTarget(worktree: worktree, project: project)
                                            }, onPathCopied: {
                                                pathCopyNotificationID = UUID()
                                            })
                            }
                        }
                        .padding(24)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: expandedDiffs)
                        .disabled(model.isProjectTransitioning)
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
