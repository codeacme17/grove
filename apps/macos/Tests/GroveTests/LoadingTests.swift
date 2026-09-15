import Foundation
import Testing
@testable import Grove
@testable import GroveCore

@MainActor @Test func fastLoadingNeverShowsAnIndicator() async throws {
    let feedback = LoadingFeedback()
    let loading = Task { await feedback.update(isLoading: true) }
    try await Task.sleep(for: .milliseconds(30))
    #expect(!feedback.isVisible)
    loading.cancel()
    await loading.value
    await feedback.update(isLoading: false)
    #expect(!feedback.isVisible)
}

@MainActor @Test func visibleLoadingHasAMinimumDurationAndSurvivesRestart() async {
    let feedback = LoadingFeedback(delay: .zero, minimumDuration: .milliseconds(100))
    await feedback.update(isLoading: true)
    #expect(feedback.isVisible)
    let finish = Task { await feedback.update(isLoading: false) }
    await Task.yield()
    #expect(feedback.isVisible)
    finish.cancel()
    await finish.value
    await feedback.update(isLoading: true)
    #expect(feedback.isVisible)
    await feedback.update(isLoading: false)
    #expect(!feedback.isVisible)
}

private actor DiffReadGate {
    private var pending: [String: CheckedContinuation<DiffContent, any Error>] = [:]

    func read(_ selection: FileDiffSelection) async throws -> DiffContent {
        try await withCheckedThrowingContinuation { pending[selection.change.path] = $0 }
    }

    func isWaiting(for path: String) -> Bool { pending[path] != nil }

    func finish(_ path: String, text: String) {
        pending.removeValue(forKey: path)?.resume(returning: DiffContent(text: text, isTruncated: false))
    }

    func fail(_ path: String) {
        pending.removeValue(forKey: path)?.resume(throwing: GroveError.message("Read failed"))
    }
}

@MainActor @Test func diffRefreshKeepsTheDocumentAndDiscardsObsoleteResponses() async throws {
    let gate = DiffReadGate()
    let model = FileDiffModel(read: { try await gate.read($0) })
    let worktree = Worktree(path: "/repo", head: nil, branch: "refs/heads/main", isBare: false,
                            isDetached: false, lockReason: nil, pruneReason: nil)
    let project = Project(name: "Repo", gitDirectory: "/repo/.git")
    func selection(_ path: String) -> FileDiffSelection {
        FileDiffSelection(change: WorktreeChange(path: path, originalPath: nil, status: "M", section: .unstaged),
                          worktree: worktree, project: project)
    }
    func waitForRead(_ path: String) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !(await gate.isWaiting(for: path)) && ContinuousClock.now < deadline { await Task.yield() }
        #expect(await gate.isWaiting(for: path))
    }
    let first = Task { await model.load(selection("a.swift")) }
    try await waitForRead("a.swift")
    await gate.finish("a.swift", text: "first diff")
    await first.value
    #expect(model.snapshot?.content.text == "first diff")

    let refresh = Task { await model.load(selection("a.swift")) }
    try await waitForRead("a.swift")
    #expect(model.isLoading)
    #expect(model.snapshot?.content.text == "first diff")
    #expect(model.snapshot?.selection.change.path == "a.swift")

    let next = Task { await model.load(selection("b.swift")) }
    try await waitForRead("b.swift")
    #expect(model.snapshot?.selection.change.path == "a.swift")
    #expect(model.snapshot?.content.text == "first diff")
    await gate.finish("b.swift", text: "second diff")
    await next.value
    await gate.finish("a.swift", text: "obsolete diff")
    await refresh.value
    #expect(model.snapshot?.selection.change.path == "b.swift")
    #expect(model.snapshot?.content.text == "second diff")
    #expect(!model.isLoading)

    let failure = Task { await model.load(selection("b.swift")) }
    try await waitForRead("b.swift")
    await gate.fail("b.swift")
    await failure.value
    #expect(model.errorMessage != nil)
    #expect(model.snapshot?.content.text == "second diff")
}
