import AppKit
import SwiftUI

@main
struct GroveApp: App {
    @State private var model = WorkspaceModel()
    @State private var windows = MainWindowActions()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Grove", id: MainWindowActions.sceneID) {
            ContentView(model: model)
                .frame(minWidth: 780, minHeight: 500)
                .groveBranding()
                .groveAppearance()
                .background(MainWindowBridge(actions: windows).frame(width: 0, height: 0))
        }
        .defaultSize(width: 1080, height: 720)
        .commands {
            GroveBrandCommands()
            GroveAppearanceCommands()
            GroveProjectCommands(model: model, windows: windows)
            CommandGroup(after: .newItem) {
                Button("Refresh Worktrees", action: model.refresh)
                    .keyboardShortcut("r")
                    .disabled(model.selectedProject == nil)
            }
        }
        GroveMenuBar(model: model, windows: windows)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
