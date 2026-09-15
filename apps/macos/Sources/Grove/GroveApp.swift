import AppKit
import SwiftUI

@main
struct GroveApp: App {
    @State private var model = WorkspaceModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Grove", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 780, minHeight: 500)
                .groveBranding()
                .groveAppearance()
        }
        .defaultSize(width: 1080, height: 720)
        .commands {
            GroveBrandCommands()
            GroveAppearanceCommands()
            CommandGroup(replacing: .newItem) {
                Button("Add Project…", action: model.chooseProject)
                    .keyboardShortcut("o")
                    .disabled(model.isAdding || !model.storageReady)
            }
            CommandGroup(after: .newItem) {
                Button("Refresh Worktrees", action: model.refresh)
                    .keyboardShortcut("r")
                    .disabled(model.selectedProject == nil)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
