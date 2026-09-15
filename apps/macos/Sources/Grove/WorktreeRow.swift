import AppKit
import GroveCore
import SwiftUI

struct WorktreeRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let worktree: Worktree
    let project: Project
    let isMain: Bool
    let model: WorkspaceModel
    @Binding var isDiffExpanded: Bool
    @Binding var selectedChange: WorktreeChange?
    let onDiffRefresh: () -> Void
    @State private var isHoveringPath = false
    let onSwitchBranch: () -> Void
    private var exists: Bool { FileManager.default.fileExists(atPath: worktree.path) }
    private var canOperate: Bool { !worktree.isBare && exists && worktree.pruneReason == nil }

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
                if canOperate {
                    if model.busyWorktreePath == worktree.path {
                        ProgressView().controlSize(.small)
                            .frame(width: 24, height: 24)
                            .help("Updating worktree…")
                    } else {
                        Button {
                            Task {
                                do { try await model.pull(worktree, project: project) }
                                catch { model.actionError = "Could not pull \(worktree.name).\n\(error.localizedDescription)" }
                            }
                        } label: {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 16))
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .disabled(model.busyWorktreePath != nil || worktree.isDetached)
                        .accessibilityLabel("Pull \(worktree.name)")
                        .help(worktree.isDetached ? "Switch to a branch before pulling." : "Pull from upstream")
                    }
                }
                Menu {
                    Button("Copy Path") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(worktree.path, forType: .string)
                    }
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: worktree.path)])
                    }.disabled(!exists)
                } label: { Image(systemName: "ellipsis").frame(height: 24) }
                    .menuStyle(.borderlessButton).fixedSize()
                    .accessibilityLabel("Actions for \(worktree.name)")
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if canOperate {
                    Button(action: onSwitchBranch) {
                        Text(worktree.path)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(isHoveringPath ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)
                    .onHover { isHoveringPath = $0 }
                    .disabled(model.busyWorktreePath != nil)
                    .accessibilityLabel("Switch branch for \(worktree.name)")
                    .help("Click to switch branch\n\(worktree.path)")
                } else {
                    Text(worktree.path).foregroundStyle(.secondary)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if canOperate {
                    Button { isDiffExpanded.toggle() } label: {
                        Label(isDiffExpanded ? "Hide Diff" : "Show Diff",
                              systemImage: isDiffExpanded ? "chevron.up" : "chevron.down")
                    }
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
                if isDiffExpanded {
                    WorktreeDiffView(worktree: worktree, project: project, isBusy: model.busyWorktreePath != nil,
                                     refreshedAt: model.updatedAt, selectedChange: $selectedChange, onRefresh: onDiffRefresh)
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
