import Observation
import SwiftUI

@MainActor @Observable
final class LoadingFeedback {
    private(set) var isVisible = false
    private var appearedAt: ContinuousClock.Instant?
    private let delay: Duration
    private let minimumDuration: Duration

    init(delay: Duration = .milliseconds(250), minimumDuration: Duration = .milliseconds(300)) {
        self.delay = delay
        self.minimumDuration = minimumDuration
    }

    func update(isLoading: Bool) async {
        do {
            if isLoading {
                guard !isVisible else { return }
                try await Task.sleep(for: delay)
                try Task.checkCancellation()
                appearedAt = .now
                isVisible = true
            } else {
                if let appearedAt {
                    let remaining = minimumDuration - appearedAt.duration(to: .now)
                    if remaining > .zero { try await Task.sleep(for: remaining) }
                }
                try Task.checkCancellation()
                isVisible = false
                appearedAt = nil
            }
        } catch { }
    }
}

struct LoadingIndicator: View {
    let isLoading: Bool
    var label = "Loading…"
    var idleIcon: String?
    @State private var feedback = LoadingFeedback()

    var body: some View {
        ZStack {
            if let idleIcon {
                Image(systemName: idleIcon).opacity(feedback.isVisible ? 0 : 1)
            }
            ProgressView().controlSize(.small).opacity(feedback.isVisible ? 1 : 0)
        }
        .frame(width: 24, height: 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityHidden(idleIcon == nil && !feedback.isVisible)
        .help(label)
        .task(id: isLoading) { await feedback.update(isLoading: isLoading) }
    }
}
