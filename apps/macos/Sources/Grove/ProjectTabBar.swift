import GroveCore
import SwiftUI

enum ProjectNavigationPlacement: String {
    case sidebar, top
}

struct ProjectTabBar: View {
    @Bindable var model: WorkspaceModel
    let isVisible: Bool
    let onRename: (Project) -> Void
    let onSwitchToSidebar: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        ForEach(model.projects) { project in
                            ProjectTab(project: project, isSelected: model.selection == project.id,
                                       onSelect: { model.selection = project.id },
                                       onDrop: { draggedID, after in
                                           guard let source = model.projects.firstIndex(where: { $0.id == draggedID }),
                                                 let target = model.projects.firstIndex(where: { $0.id == project.id }),
                                                 source != target else { return false }
                                           model.moveProjects(from: IndexSet(integer: source), to: target + (after ? 1 : 0))
                                           return true
                                       })
                                .id(project.id)
                                .contextMenu {
                                    Button("Rename…") { onRename(project) }
                                    Button("Remove from Grove", role: .destructive) { model.remove(project) }
                                    Divider()
                                    switchToSidebarButton
                                }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .scrollIndicators(.hidden)
                .onChange(of: isVisible) { _, visible in
                    if visible, let selection = model.selection { proxy.scrollTo(selection) }
                }
                .onChange(of: model.selection, initial: true) { _, selection in
                    if let selection { proxy.scrollTo(selection) }
                }
            }
            Button(action: model.chooseProject) {
                Image(systemName: "plus")
                    .frame(width: 30, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(model.isAdding ? "Adding Project…" : "Add Project…")
            .accessibilityLabel("Add Project")
            .disabled(model.isAdding || !model.storageReady)
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .contentShape(Rectangle())
        .contextMenu { switchToSidebarButton }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Project tabs")
    }

    private var switchToSidebarButton: some View {
        Button("Switch to Sidebar", systemImage: "sidebar.left", action: onSwitchToSidebar)
    }
}

private struct ProjectTab: View {
    let project: Project
    let isSelected: Bool
    let onSelect: () -> Void
    let onDrop: (String, Bool) -> Bool
    @State private var isHovered = false
    @State private var isDropTarget = false
    @State private var tabWidth: CGFloat = 100

    var body: some View {
        Button(action: onSelect) {
            Label(project.name, systemImage: "folder")
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(minWidth: 100, maxWidth: 200, minHeight: 32)
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .draggable(project.id)
        }
        .buttonStyle(.plain)
        .background(.primary.opacity(isSelected ? 0.10 : (isHovered ? 0.05 : 0)), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.accentColor.opacity(isDropTarget ? 0.6 : 0), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .onHover { isHovered = $0 }
        .help(project.gitDirectory)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .background {
            GeometryReader { geometry in
                Color.clear.onChange(of: geometry.size.width, initial: true) { _, width in
                    tabWidth = width
                }
            }
        }
        .dropDestination(for: String.self) { items, location in
            guard items.count == 1, let id = items.first else { return false }
            return onDrop(id, location.x > tabWidth / 2)
        } isTargeted: { isDropTarget = $0 }
    }
}
