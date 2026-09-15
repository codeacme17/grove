import GroveCore
import SwiftUI

struct FileDiffSelection: Equatable {
    let change: WorktreeChange
    let worktree: Worktree
    let project: Project

    struct DocumentID: Hashable {
        let project: String
        let worktree: String
        let path: String
        let section: ChangeSection
    }

    var documentID: DocumentID {
        DocumentID(project: project.id, worktree: worktree.path, path: change.path, section: change.section)
    }
}

struct FileDiffPanel: View {
    let selection: FileDiffSelection
    let isActive: Bool
    let isBusy: Bool
    let refreshedAt: Date?
    let revision: Int
    let close: () -> Void
    @State private var preview = FileDiffModel()
    @State private var reloadID = 0

    private struct Request: Equatable {
        let selection: FileDiffSelection
        let isActive: Bool
        let isBusy: Bool
        let refreshedAt: Date?
        let revision: Int
        let reloadID: Int
    }

    var body: some View {
        let displayedSelection = preview.snapshot?.selection ?? selection
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass").foregroundStyle(.secondary)
                Text("Diff").font(.headline)
                Text(displayedSelection.worktree.name).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                Button { reloadID += 1 } label: {
                    LoadingIndicator(isLoading: preview.isLoading || isBusy,
                                     label: "Refresh file diff", idleIcon: "arrow.clockwise")
                }
                .disabled(isBusy)
                .help("Refresh file diff").accessibilityLabel("Refresh file diff")
                Button(action: close) {
                    Image(systemName: "xmark").frame(width: 24, height: 24)
                }
                .help("Close Diff").accessibilityLabel("Close Diff")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12).padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 5) {
                Text(displayedSelection.change.originalPath.map { "\($0) → \(displayedSelection.change.path)" } ?? displayedSelection.change.path)
                    .font(.system(size: 12, weight: .medium)).lineLimit(2).truncationMode(.middle)
                    .textSelection(.enabled).help(displayedSelection.change.path)
                Text(displayedSelection.change.section.title).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.035))

            if let errorMessage = preview.errorMessage {
                HStack {
                    Text(errorMessage).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                    Button("Retry") { reloadID += 1 }.disabled(isBusy)
                }.padding(12)
            }
            if let snapshot = preview.snapshot {
                let content = snapshot.content
                if content.text.isEmpty {
                    message("No textual diff available. The file may have changed; refresh the list.")
                } else {
                    DiffTextView(text: content.text)
                        .id(snapshot.selection.documentID)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if content.isTruncated {
                    Text("Preview limited to 200 KB for this file.")
                        .font(.caption).foregroundStyle(.secondary).padding(12)
                }
            } else {
                Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: Request(selection: selection, isActive: isActive, isBusy: isBusy, refreshedAt: refreshedAt,
                          revision: revision, reloadID: reloadID)) {
            guard isActive, !isBusy else { return }
            await preview.load(selection)
        }
    }

    private func message(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary)
            .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
