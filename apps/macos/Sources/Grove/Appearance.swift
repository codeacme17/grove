import AppKit
import SwiftUI

enum GroveAppearance: String, CaseIterable {
    case system, light, dark

    static let storageKey = "appearance"

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var appKitAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

private struct AppearancePicker: View {
    @AppStorage(GroveAppearance.storageKey) private var appearance: GroveAppearance = .system

    var body: some View {
        Picker("Appearance", selection: $appearance) {
            ForEach(GroveAppearance.allCases, id: \.self) { choice in
                Text(choice.title).tag(choice)
            }
        }
        .pickerStyle(.inline)
    }
}

private struct GroveAppearanceModifier: ViewModifier {
    @AppStorage(GroveAppearance.storageKey) private var appearance: GroveAppearance = .system

    func body(content: Content) -> some View {
        content
            .onChange(of: appearance, initial: true) {
                NSApplication.shared.appearance = appearance.appKitAppearance
            }
            .toolbar {
                ToolbarItem {
                    Menu { AppearancePicker() } label: {
                        Label("Appearance", systemImage: "circle.lefthalf.filled")
                    }
                    .accessibilityLabel("Appearance")
                    .help("Appearance: \(appearance.title)")
                }
            }
    }
}

struct GroveAppearanceCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Menu("Appearance") { AppearancePicker() }
        }
    }
}

extension View {
    func groveAppearance() -> some View { modifier(GroveAppearanceModifier()) }
}
