import AppKit
import SwiftUI

struct DiffWorkspaceSplit<Content: View, Panel: View>: View {
    let isPresented: Bool
    @ViewBuilder let content: () -> Content
    @ViewBuilder let panel: () -> Panel
    @State private var panelWidth: CGFloat = 520
    @State private var isHovering = false
    @GestureState private var drag: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let maximumWidth = max(300, geometry.size.width - 326)
            let restingWidth = min(maximumWidth, max(300, panelWidth))
            let width = min(maximumWidth, max(300, restingWidth - drag))
            HStack(spacing: 0) {
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                if isPresented {
                    HStack(spacing: 0) {
                        resizeHandle(width: restingWidth, maximum: maximumWidth)
                        panel().frame(width: width)
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .clipped()
    }

    private func resizeHandle(width: CGFloat, maximum: CGFloat) -> some View {
        Color.clear
            .frame(width: 6)
            .overlay {
                Rectangle().fill(.secondary.opacity(isHovering || drag != 0 ? 0.5 : 0.16))
                    .frame(width: 1).allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
                if hovering { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() }
            }
            .onDisappear { if isHovering { NSCursor.arrow.set() } }
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .updating($drag) { value, state, _ in state = value.translation.width }
                    .onEnded { value in panelWidth = min(maximum, max(300, width - value.translation.width)) }
            )
            .accessibilityLabel("Diff panel width")
            .accessibilityValue("\(Int(width)) points")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: panelWidth = min(maximum, width + 20)
                case .decrement: panelWidth = max(300, width - 20)
                @unknown default: break
                }
            }
    }
}
