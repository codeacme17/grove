import Foundation

public enum ChangeSection: String, CaseIterable, Sendable {
    case conflicted, staged, unstaged, untracked
}

public struct WorktreeChange: Identifiable, Hashable, Sendable {
    public var id: Self { self }
    public let path: String
    public let originalPath: String?
    public let status: String
    public let section: ChangeSection

    static func parseStatus(_ data: Data) throws -> [WorktreeChange] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw GroveError.message("A changed path is not valid UTF-8.")
        }
        let records = text.split(separator: "\0", omittingEmptySubsequences: false)
        var changes: [WorktreeChange] = []
        var index = 0
        while index < records.count, !records[index].isEmpty {
            let record = records[index]
            index += 1
            guard record.utf8.count > 3, record.dropFirst(2).first == " " else {
                throw GroveError.message("Git returned an unsupported change record.")
            }
            let status = String(record.prefix(2))
            let path = String(record.dropFirst(3))
            var originalPath: String?
            if status.contains("R") || status.contains("C") {
                guard index < records.count, !records[index].isEmpty else {
                    throw GroveError.message("Git returned an incomplete rename record.")
                }
                originalPath = String(records[index])
                index += 1
            }
            if ["DD", "AU", "UD", "UA", "DU", "AA", "UU"].contains(status) {
                changes.append(Self(path: path, originalPath: nil, status: "U", section: .conflicted))
            } else if status == "??" {
                changes.append(Self(path: path, originalPath: nil, status: "U", section: .untracked))
            } else {
                for (code, section) in zip(status, [ChangeSection.staged, .unstaged]) where code != " " && code != "!" {
                    changes.append(Self(path: path, originalPath: code == "R" || code == "C" ? originalPath : nil,
                                        status: String(code), section: section))
                }
            }
        }
        return changes.sorted { $0.path < $1.path }
    }
}
