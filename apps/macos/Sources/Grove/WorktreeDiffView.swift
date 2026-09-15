import AppKit
import GroveCore
import SwiftUI

struct WorktreeDiffView: View {
    let worktree: Worktree
    let project: Project
    let isBusy: Bool
    let refreshedAt: Date?
    @State private var changes: [WorktreeChange]?
    @State private var errorMessage: String?
    @Binding var selectedChange: WorktreeChange?
    let onRefresh: () -> Void
    @State private var collapsedSections: Set<ChangeSection> = []
    @State private var reloadID = 0

    private struct Request: Equatable {
        let reloadID: Int
        let isBusy: Bool
        let refreshedAt: Date?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Local Changes").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Button { reloadID += 1 } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Refresh changes")
                .accessibilityLabel("Refresh changes")
                .disabled(isBusy)
            }
            if isBusy {
                Text("Waiting for the Git operation to finish…").foregroundStyle(.secondary)
            } else if let changes {
                if changes.isEmpty {
                    Text("No local changes").font(.callout).foregroundStyle(.secondary).padding(.vertical, 8)
                } else {
                    fileList(changes)
                }
            } else if let errorMessage {
                Text(errorMessage).font(.callout).foregroundStyle(.red).textSelection(.enabled)
            } else {
                ProgressView("Reading changes…").controlSize(.small).padding(.vertical, 8)
            }
        }
        .task(id: Request(reloadID: reloadID, isBusy: isBusy, refreshedAt: refreshedAt)) {
            changes = nil
            errorMessage = nil
            guard !isBusy else { return }
            do {
                let result = try await WorktreeRepository().changes(in: worktree, project: project)
                try Task.checkCancellation()
                changes = result
                if let selectedChange {
                    self.selectedChange = result.first { $0.path == selectedChange.path && $0.section == selectedChange.section }
                    onRefresh()
                }
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func fileList(_ changes: [WorktreeChange]) -> some View {
        let groups = ChangeSection.allCases.filter { section in changes.contains { $0.section == section } }
        let visibleRows = changes.filter { !collapsedSections.contains($0.section) }.count
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(groups, id: \.self) { section in
                    let files = changes.filter { $0.section == section }
                    let isCollapsed = collapsedSections.contains(section)
                    Button {
                        if isCollapsed {
                            collapsedSections.remove(section)
                        } else {
                            collapsedSections.insert(section)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                                .font(.system(size: 10, weight: .semibold)).frame(width: 14)
                            Text(section.title).font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Text("\(files.count)").font(.system(size: 10, weight: .medium)).monospacedDigit()
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.primary.opacity(0.08), in: Capsule())
                        }
                        .padding(.horizontal, 6)
                        .frame(height: 30)
                        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 4))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(section.title), \(files.count) files, \(isCollapsed ? "collapsed" : "expanded")")
                    if !isCollapsed {
                        ForEach(files) { change in
                            ChangeFileRow(change: change, isSelected: selectedChange == change) {
                                selectedChange = change
                            }
                        }
                    }
                }
            }
        }
        .frame(height: min(CGFloat(groups.count * 30 + visibleRows * 28), 280))
    }
}

extension ChangeSection {
    var title: String {
        switch self {
        case .conflicted: "Merge Changes"
        case .staged: "Staged Changes"
        case .unstaged: "Changes"
        case .untracked: "Untracked"
        }
    }
}

private struct ChangeFileRow: View {
    let change: WorktreeChange
    let isSelected: Bool
    let select: () -> Void
    @State private var isHovering = false

    private var filename: String { (change.path as NSString).lastPathComponent }
    private var directory: String { (change.path as NSString).deletingLastPathComponent }
    private var icon: String {
        switch (filename as NSString).pathExtension.lowercased() {
        case "swift": "swift"
        case "json", "yml", "yaml", "toml": "curlybraces"
        case "md", "txt": "doc.text"
        case "png", "jpg", "jpeg", "gif", "svg", "webp", "ico": "photo"
        default: change.path.hasSuffix("/") ? "folder" : "doc"
        }
    }
    private var statusColor: Color {
        if change.section == .conflicted { return .red }
        switch change.status {
        case "A", "U": return .green
        case "D": return .red
        case "R", "C": return .teal
        default: return .orange
        }
    }

    var body: some View {
        Button(action: select) {
            HStack(spacing: 7) {
                Image(systemName: icon).foregroundStyle(.secondary).frame(width: 16)
                Text(filename).lineLimit(1).truncationMode(.middle).layoutPriority(1)
                if !directory.isEmpty {
                    Text(directory).font(.system(size: 11)).foregroundStyle(.tertiary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 4)
                Text(change.status).font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(statusColor).frame(width: 16)
            }
            .font(.system(size: 12))
            .padding(.leading, 22).padding(.trailing, 8)
            .frame(height: 28)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(isHovering ? 0.045 : 0),
                        in: RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(change.originalPath.map { "\($0) → \(change.path)" } ?? change.path)
        .accessibilityLabel("\(change.path), \(change.section.title), \(change.status)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
