import AppKit
import SwiftUI

@MainActor
final class MainWindowActions {
    static let sceneID = "main"
    private weak var window: NSWindow?
    private var presentationRequested = false
    private var pendingAction: ((NSWindow) -> Void)?

    func show(using openWindow: OpenWindowAction, then action: ((NSWindow) -> Void)? = nil) {
        pendingAction = action
        presentationRequested = true
        openWindow(id: Self.sceneID)
        presentIfReady()
    }

    func attach(_ window: NSWindow) {
        self.window = window
        presentIfReady()
    }

    private func presentIfReady() {
        guard presentationRequested, let window else { return }
        presentationRequested = false
        let action = pendingAction
        pendingAction = nil
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        action?(window)
    }
}

struct MainWindowBridge: NSViewRepresentable {
    let actions: MainWindowActions

    func makeNSView(context: Context) -> WindowAttachmentView {
        WindowAttachmentView(actions: actions)
    }

    func updateNSView(_ nsView: WindowAttachmentView, context: Context) {}
}

final class WindowAttachmentView: NSView {
    private let actions: MainWindowActions

    init(actions: MainWindowActions) {
        self.actions = actions
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.window === window else { return }
            self.actions.attach(window)
        }
    }
}
