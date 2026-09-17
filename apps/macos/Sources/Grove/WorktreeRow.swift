import AppKit
import GroveCore
import SwiftUI

struct WorktreeRow: View {
    @State private var hasOpenedDiff = false
    @State private var isPreparingDiff = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    let worktree: Worktree
    let project: Project
    let isMain: Bool
    let model: WorkspaceModel
    @Binding var isDiffExpanded: Bool
    @Binding var selectedChange: WorktreeChange?
    let onDiffRefresh: () -> Void
    @State private var isHoveringBranch = false
    @State private var isHoveringPath = false
    let onSwitchBranch: () -> Void
    let onPathCopied: () -> Void
    private var exists: Bool { FileManager.default.fileExists(atPath: worktree.path) }
    private var canOperate: Bool { !worktree.isBare && exists && worktree.pruneReason == nil }

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
                            .disabled(model.busyWorktreePath != nil)
                            .accessibilityLabel("Switch branch for \(worktree.name), current revision \(worktree.revision)")
                            .help("Click to switch branch\n\(worktree.revision)")
                        } else {
                            revisionLabel.foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                    Spacer(minLength: 0)
                    if canOperate {
                        Button {
                            Task {
                                do { try await model.pull(worktree, project: project) }
                                catch { model.actionError = "Could not pull \(worktree.name).\n\(error.localizedDescription)" }
                            }
                        } label: {
                            LoadingIndicator(isLoading: model.busyWorktreePath == worktree.path,
                                             label: "Pull from upstream", idleIcon: "arrow.down.circle")
                                .font(.system(size: 16))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .disabled(model.busyWorktreePath != nil || worktree.isDetached)
                        .accessibilityLabel("Pull \(worktree.name)")
                        .help(worktree.isDetached ? "Switch to a branch before pulling." : "Pull from upstream")
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
                    if canOperate {
                        Button {
                            if isDiffExpanded {
                                isDiffExpanded = false
                            } else if model.changesModel(for: worktree, project: project).changes != nil {
                                isDiffExpanded = true
                            } else {
                                isPreparingDiff.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                LoadingIndicator(isLoading: isPreparingDiff, label: "Show changes",
                                                 idleIcon: isDiffExpanded ? "chevron.up" : "chevron.down")
                                Text(isDiffExpanded ? "Hide Diff" : "Show Diff")
                            }
                        }
                        .disabled(model.busyWorktreePath != nil)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .fixedSize()
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
                    if model.busyWorktreePath != worktree.path, let message = model.worktreeMessages[worktree.path] {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .transaction { $0.animation = nil }
            if canOperate && (hasOpenedDiff || isDiffExpanded) {
                WorktreeDiffView(worktree: worktree, project: project,
                                 isBusy: model.busyWorktreePath != nil || model.isLoading,
                                 isExpanded: isDiffExpanded,
                                 refreshedAt: model.updatedAt,
                                 state: model.changesModel(for: worktree, project: project),
                                 selectedChange: $selectedChange, onRefresh: onDiffRefresh)
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
        .task(id: isPreparingDiff) {
            guard isPreparingDiff else { return }
            await model.changesModel(for: worktree, project: project).load(in: worktree, project: project)
            guard !Task.isCancelled else { return }
            isPreparingDiff = false
            isDiffExpanded = true
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
