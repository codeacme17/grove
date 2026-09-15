import AppKit
import SwiftUI

@MainActor
enum GroveBrand {
    static let bundle: Bundle = {
        if let url = Bundle.main.url(forResource: "Grove_Grove", withExtension: "bundle"),
           let packaged = Bundle(url: url) {
            return packaged
        }
        return Bundle.module
    }()

    private static let light = load("AppIcon")
    private static let dark = load("AppIconDark")

    static func image(for scheme: ColorScheme) -> NSImage {
        scheme == .dark ? dark : light
    }

    private static func load(_ name: String) -> NSImage {
        guard let url = bundle.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            preconditionFailure("Missing bundled Grove artwork: \(name)")
        }
        return image
    }
}

struct GroveLogo: View {
    var size: CGFloat = 44
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(nsImage: GroveBrand.image(for: colorScheme))
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct GroveEmptyStateLabel: View {
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            GroveLogo(size: 112)
            Text(title).font(.title2.weight(.semibold))
        }
    }
}

private struct GroveBranding: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.onChange(of: colorScheme, initial: true) {
            NSApplication.shared.applicationIconImage = GroveBrand.image(for: colorScheme)
        }
    }
}

extension View {
    func groveBranding() -> some View { modifier(GroveBranding()) }
}

struct GroveBrandCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Grove") {
                NSApplication.shared.orderFrontStandardAboutPanel(options: [
                    .applicationIcon: NSApplication.shared.applicationIconImage
                        ?? GroveBrand.image(for: .light)
                ])
            }
        }
    }
}
