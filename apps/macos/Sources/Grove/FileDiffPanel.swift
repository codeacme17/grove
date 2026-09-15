import GroveCore
import SwiftUI

struct FileDiffSelection: Equatable {
    let change: WorktreeChange
    let worktree: Worktree
    let project: Project
}

struct FileDiffPanel: View {
    let selection: FileDiffSelection
    let isBusy: Bool
    let refreshedAt: Date?
    let revision: Int
    let close: () -> Void
    @State private var content: DiffContent?
    @State private var errorMessage: String?
    @State private var reloadID = 0

    private struct Request: Equatable {
        let selection: FileDiffSelection
        let isBusy: Bool
        let refreshedAt: Date?
        let revision: Int
        let reloadID: Int
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass").foregroundStyle(.secondary)
                Text("Diff").font(.headline)
                Text(selection.worktree.name).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                Button { reloadID += 1 } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 24, height: 24)
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
                Text(selection.change.originalPath.map { "\($0) → \(selection.change.path)" } ?? selection.change.path)
                    .font(.system(size: 12, weight: .medium)).lineLimit(2).truncationMode(.middle)
                    .textSelection(.enabled).help(selection.change.path)
                Text(selection.change.section.title).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.035))

            if isBusy {
                message("Waiting for the Git operation to finish…")
            } else if let content {
                if content.text.isEmpty {
                    message("No textual diff available. The file may have changed; refresh the list.")
                } else {
                    DiffTextView(text: content.text)
                        .id(selection.change)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if content.isTruncated {
                    Text("Preview limited to 200 KB for this file.")
                        .font(.caption).foregroundStyle(.secondary).padding(12)
                }
            } else if let errorMessage {
                VStack(spacing: 12) {
                    Text(errorMessage).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                    Button("Retry") { reloadID += 1 }
                }
                .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView("Reading diff…").controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: Request(selection: selection, isBusy: isBusy, refreshedAt: refreshedAt,
                          revision: revision, reloadID: reloadID)) {
            content = nil
            errorMessage = nil
            guard !isBusy else { return }
            do {
                let result = try await WorktreeRepository().diff(for: selection.change, in: selection.worktree,
                                                                 project: selection.project)
                try Task.checkCancellation()
                content = result
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary)
            .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
