import AppKit
import GroveCore
import SwiftUI

struct WorktreeRow: View {
    @State private var hasOpenedDiff = false
    @State private var changesReloadID = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    let worktree: Worktree
    let project: Project
    let isMain: Bool
    let model: WorkspaceModel
    @State var changesState: WorktreeChangesModel
    @Binding var isDiffExpanded: Bool
    @Binding var selectedChange: WorktreeChange?
    let onDiffRefresh: () -> Void
    @State private var isHoveringBranch = false
    @State private var isHoveringPath = false
    let onSwitchBranch: () -> Void
    let onDelete: () -> Void
    let onPathCopied: () -> Void
    private var exists: Bool { FileManager.default.fileExists(atPath: worktree.path) }
    private var canOperate: Bool { !worktree.isBare && exists && worktree.pruneReason == nil }
    private var isBusy: Bool { model.isPerformingGitOperation || model.isLoading || model.isProjectTransitioning }
    private var pullTooltip: String {
        worktree.isDetached ? "Switch to a branch before pulling." : "Pull latest changes from upstream"
    }

    private struct ChangesRequest: Equatable {
        let reloadID: Int
        let refreshedAt: Date?
        let isBusy: Bool
        let canOperate: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                        if canOperate {
                            Button(action: onSwitchBranch) {
                                revisionLabel
                                    .foregroundStyle(isHoveringBranch ? .primary : .secondary)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .onHover { isHoveringBranch = $0 }
                            .disabled(model.isPerformingGitOperation)
                            .accessibilityLabel("Switch branch for \(worktree.name), current revision \(worktree.revision)")
                            .help("Click to switch branch\n\(worktree.revision)")
                        } else {
                            revisionLabel.foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        if canOperate {
                            Button {
                                Task {
                                    do { try await model.pull(worktree, project: project) }
                                    catch { model.actionError = "Could not pull \(worktree.name).\n\(error.localizedDescription)" }
                                }
                            } label: {
                                LoadingIndicator(isLoading: model.busyWorktreePath == worktree.path,
                                                 label: pullTooltip, idleIcon: "arrow.down")
                                    .modifier(WorktreeActionChrome())
                            }
                            .buttonStyle(.plain)
                            .disabled(model.isPerformingGitOperation || worktree.isDetached)
                            .accessibilityLabel("Pull \(worktree.name)")
                            .help(pullTooltip)
                        }

                        Menu {
                            Button("Delete Worktree…", role: .destructive, action: onDelete)
                                .disabled(deletionUnavailableReason != nil)
                            if let reason = deletionUnavailableReason { Text(reason) }
                        } label: {
                            Image(systemName: "ellipsis")
                                .frame(width: 24, height: 24)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .modifier(WorktreeActionChrome())
                        .disabled(isBusy)
                        .help(deletionUnavailableReason ?? "Worktree actions")
                        .accessibilityLabel("Actions for \(worktree.name)")
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Button {
                            NSPasteboard.general.clearContents()
                            if NSPasteboard.general.setString(worktree.path, forType: .string) {
                                onPathCopied()
                            }
                        } label: {
                            Text(worktree.path)
                                .foregroundStyle(isHoveringPath ? .primary : .secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onHover { isHoveringPath = $0 }
                        .accessibilityLabel("Copy path: \(worktree.path)")
                        .help("Click to copy path\n\(worktree.path)")

                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: worktree.path)])
                        } label: {
                            Image(systemName: "arrow.up.right.square")
                                .frame(width: 20, height: 20)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .disabled(!exists)
                        .accessibilityLabel("Reveal \(worktree.name) in Finder")
                        .help("Reveal in Finder")
                    }
                    Spacer(minLength: 0)
                    if canOperate, let count = changesState.changedFileCount, count > 0 {
                        Button { isDiffExpanded.toggle() } label: {
                            HStack(spacing: 4) {
                                LoadingIndicator(isLoading: changesState.isLoading, label: "Refresh changes",
                                                 idleIcon: isDiffExpanded ? "chevron.up" : "chevron.down")
                                Text(isDiffExpanded ? "Hide Diff" : "Show Diff")
                                Text("(\(count))").monospacedDigit()
                            }
                        }
                        .disabled(isBusy)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .accessibilityLabel("\(isDiffExpanded ? "Hide" : "Show") diff, \(count) changed files")
                    }
                }
                .font(.caption)
                if worktree.isDetached || worktree.lockReason != nil || worktree.pruneReason != nil || !exists {
                    HStack(spacing: 8) {
                        if worktree.isDetached { badge("Detached HEAD") }
                        if let reason = worktree.lockReason { badge("Locked").help(reason.isEmpty ? "Locked by Git" : reason) }
                        if let reason = worktree.pruneReason { badge("Prunable").help(reason) }
                        if !exists { badge("Path unavailable") }
                    }
                }
                if canOperate {
                    if !isDiffExpanded, let error = changesState.errorMessage {
                        HStack {
                            Text("Could not read changes: \(error)")
                                .foregroundStyle(.red).textSelection(.enabled)
                            Button("Retry") { changesReloadID += 1 }
                                .disabled(isBusy)
                        }
                        .font(.caption)
                    }
                    if model.busyWorktreePath != worktree.path, let message = model.worktreeMessages[worktree.path] {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .transaction { $0.animation = nil }
            if canOperate && (hasOpenedDiff || isDiffExpanded) {
                WorktreeDiffView(state: changesState, selectedChange: $selectedChange,
                                 isBusy: isBusy, onRetry: { changesReloadID += 1 })
                    .fixedSize(horizontal: false, vertical: true)
                    .transaction {
                        $0.animation = nil
                        $0.disablesAnimations = true
                    }
                    .padding(.top, 12)
                    .frame(height: isDiffExpanded ? nil : 0, alignment: .top)
                    .clipped()
                    .allowsHitTesting(isDiffExpanded)
                    .accessibilityHidden(!isDiffExpanded)
                    .transition(.asymmetric(insertion: .opacity, removal: .identity))
            }
        }
        .task(id: ChangesRequest(reloadID: changesReloadID, refreshedAt: model.updatedAt,
                                 isBusy: isBusy, canOperate: canOperate)) {
            guard canOperate, !isBusy else { return }
            await changesState.observe(in: worktree, project: project) {
                guard let changes = changesState.changes else { return }
                if let selectedChange {
                    self.selectedChange = changes.first { $0.path == selectedChange.path && $0.section == selectedChange.section }
                }
                if changes.isEmpty { isDiffExpanded = false }
                onDiffRefresh()
            }
        }
        .onChange(of: isDiffExpanded, initial: true) { _, expanded in
            if expanded { hasOpenedDiff = true }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colorScheme == .light ? AnyShapeStyle(GroveBrand.lightBackground) : AnyShapeStyle(.background),
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
        // Include the card decorations so their bounds shrink with the clipped content.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: isDiffExpanded)
    }

    private var deletionUnavailableReason: String? {
        if worktree.isBare { return "Bare repositories cannot be deleted." }
        if isMain { return "The main worktree cannot be deleted." }
        if !exists || worktree.pruneReason != nil { return "Path unavailable. Stale-registration cleanup is not supported." }
        if worktree.lockReason != nil { return "Unlock this worktree outside Grove first." }
        if worktree.isDetached { return "Switch to a local branch before deleting this worktree." }
        if let count = changesState.changedFileCount, count > 0 { return "Preserve local changes before deleting this worktree." }
        return nil
    }

    private var revisionLabel: some View {
        Label(worktree.revision, systemImage: worktree.isDetached ? "circle.dotted" : "arrow.triangle.branch")
            .font(.system(.callout, design: .monospaced))
    }

    private func badge(_ text: String) -> some View {
        Text(text).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
    }
}

private struct WorktreeActionChrome: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func body(content: Content) -> some View {
        let highlighted = isEnabled && isHovering
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        content
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(highlighted ? .primary : .secondary)
            .frame(width: 30, height: 30)
            .background(.primary.opacity(highlighted ? 0.1 : (colorScheme == .dark ? 0.05 : 0.03)), in: shape)
            .overlay(shape.strokeBorder(.primary.opacity(highlighted ? 0.16 : 0.07)))
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(shape)
            .onHover { isHovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: highlighted)
    }
}
