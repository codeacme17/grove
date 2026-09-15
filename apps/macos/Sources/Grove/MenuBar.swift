import AppKit
import SwiftUI

@MainActor
private enum MenuBarArtwork {
    static let image: NSImage = {
        guard let url = GroveBrand.bundle.url(forResource: "MenuBarTemplate", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            preconditionFailure("Missing bundled menu-bar artwork")
        }
        image.size = NSSize(width: 22, height: 22)
        image.isTemplate = true
        return image
    }()
}

struct GroveMenuBar: Scene {
    let model: WorkspaceModel
    let windows: MainWindowActions

    var body: some Scene {
        MenuBarExtra {
            GroveStatusMenu(model: model, windows: windows)
        } label: {
            Image(nsImage: MenuBarArtwork.image)
                .accessibilityLabel("Grove")
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct GroveStatusMenu: View {
    let model: WorkspaceModel
    let windows: MainWindowActions
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Grove") { windows.show(using: openWindow) }
        Button("Add Project…") {
            windows.show(using: openWindow, then: model.chooseProject(in:))
        }
        .disabled(model.isAdding || !model.storageReady)
        Divider()
        if let project = model.selectedProject {
            Text(project.name)
            Button("Refresh Worktrees", action: model.refresh)
                .disabled(model.isLoading)
        } else {
            Text("No project selected")
        }
        Divider()
        Button("Quit Grove") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

struct GroveProjectCommands: Commands {
    let model: WorkspaceModel
    let windows: MainWindowActions
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Project…") {
                windows.show(using: openWindow, then: model.chooseProject(in:))
            }
            .keyboardShortcut("o")
            .disabled(model.isAdding || !model.storageReady)
        }
    }
}
