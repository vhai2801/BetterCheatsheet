import SwiftUI
import UniformTypeIdentifiers

/// Horizontal, scrollable tab bar. Tabs truncate their name when there are too
/// many to fit; hovering a tab smoothly expands it to show the full name.
/// No limit on tab count. Includes a "+" control to add new tabs, and tabs
/// can be dragged to reorder them.
struct TabBarView: View {
    @ObservedObject var appState: AppState
    var allowAdding: Bool = true
    var showsSettingsTab: Bool = false
    /// Overlay-only: shows a pinned "..." button that opens the main editor
    /// window, since the overlay itself has no title bar/Dock icon to click.
    var onOpenMainWindow: (() -> Void)? = nil

    @State private var hoveredTabID: UUID?
    @State private var dropTargetTabID: UUID?
    @State private var hoverWorkItem: DispatchWorkItem?
    @State private var isAddingTab = false
    @State private var newTabName = ""
    @FocusState private var isNewTabFieldFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(appState.tabs) { tab in
                        tabButton(for: tab)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }

            // Fixed outside the scroll view, alongside Settings, so neither
            // ever gets pushed out of view by tab overflow.
            if allowAdding {
                addTabControl
            }

            if showsSettingsTab {
                settingsIconButton
                    .padding(.trailing, 8)
            }

            if let onOpenMainWindow {
                openMainWindowButton(action: onOpenMainWindow)
                    .padding(.trailing, 8)
            }
        }
        .frame(height: 34)
        .background(.thinMaterial)
    }

    private func openMainWindowButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "ellipsis")
                .font(.system(size: 14))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help("Open Better Cheatsheet")
    }

    private var settingsIconButton: some View {
        Button(action: selectSettings) {
            Image(systemName: "gearshape")
                .font(.system(size: 14))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .foregroundStyle(appState.isShowingSettings ? Color.accentColor : Color.primary)
        .help("Settings")
    }

    @ViewBuilder
    private func tabButton(for tab: TabItem) -> some View {
        TabButton(
            tab: tab,
            isSelected: tab.id == appState.selectedTabID,
            isHovered: hoveredTabID == tab.id,
            isDropTarget: dropTargetTabID == tab.id,
            onSelect: { selectTab(tab) },
            onRename: { renameTab(tab, to: $0) },
            onDelete: { appState.deleteTab(id: tab.id) }
        )
        .onHover { hovering in setHovered(tab, hovering: hovering) }
        .onDrag { NSItemProvider(object: tab.id.uuidString as NSString) }
        .onDrop(of: [.text], delegate: TabDropDelegate(
            targetTab: tab,
            appState: appState,
            dropTargetTabID: $dropTargetTabID
        ))
    }

    private func selectTab(_ tab: TabItem) {
        appState.isShowingSettings = false
        appState.selectedTabID = tab.id
    }

    private func selectSettings() {
        appState.isShowingSettings = true
    }

    private func renameTab(_ tab: TabItem, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appState.renameTab(id: tab.id, to: trimmed)
    }

    /// Debounced so quickly scrolling/passing the cursor over several tabs
    /// (trackpad swipe over the tab strip) doesn't trigger the hover-expand
    /// animation on every tab it crosses - only a genuine pause does.
    private func setHovered(_ tab: TabItem, hovering: Bool) {
        hoverWorkItem?.cancel()
        if hovering {
            let workItem = DispatchWorkItem { hoveredTabID = tab.id }
            hoverWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
        } else if hoveredTabID == tab.id {
            hoveredTabID = nil
        }
    }

    @ViewBuilder
    private var addTabControl: some View {
        if isAddingTab {
            TextField("Tab name", text: $newTabName)
                .textFieldStyle(.plain)
                .frame(width: 100)
                .padding(.horizontal, 8)
                .focused($isNewTabFieldFocused)
                .onAppear { isNewTabFieldFocused = true }
                .onSubmit { commitNewTab() }
                .onExitCommand { isAddingTab = false; newTabName = "" }
                .onChange(of: isNewTabFieldFocused) { focused in
                    if !focused { commitNewTab() }
                }
        } else {
            Button {
                newTabName = ""
                isAddingTab = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .focusable(false)
            .padding(.horizontal, 8)
            .help("Add tab")
        }
    }

    private func commitNewTab() {
        let trimmed = newTabName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            appState.addTab(named: trimmed)
        }
        newTabName = ""
        isAddingTab = false
    }
}

private struct TabButton: View {
    let tab: TabItem
    let isSelected: Bool
    let isHovered: Bool
    let isDropTarget: Bool
    var onSelect: () -> Void
    var onRename: (String) -> Void
    var onDelete: () -> Void

    @State private var isRenaming = false
    @State private var draftName = ""
    @FocusState private var isRenameFieldFocused: Bool

    var body: some View {
        Group {
            if isRenaming {
                TextField("Tab name", text: $draftName)
                    .textFieldStyle(.plain)
                    .frame(minWidth: 60)
                    .focused($isRenameFieldFocused)
                    .onAppear { isRenameFieldFocused = true }
                    .onSubmit { commitRename() }
                    .onExitCommand { isRenaming = false }
                    .onChange(of: isRenameFieldFocused) { focused in
                        if !focused { commitRename() }
                    }
            } else {
                Text(tab.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: isHovered, vertical: false)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: isRenaming || isHovered ? nil : 110, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    isDropTarget ? Color.accentColor : (isSelected ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.2)),
                    lineWidth: isDropTarget ? 2 : 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            draftName = tab.name
            isRenaming = true
        }
        .onTapGesture(count: 1) {
            onSelect()
        }
        .contextMenu {
            Button("Rename") {
                draftName = tab.name
                isRenaming = true
            }
            Button("Delete", role: .destructive, action: onDelete)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isHovered)
    }

    private func commitRename() {
        onRename(draftName)
        isRenaming = false
    }
}

/// Dropping a dragged tab onto another moves it to sit right before that tab.
private struct TabDropDelegate: DropDelegate {
    let targetTab: TabItem
    let appState: AppState
    @Binding var dropTargetTabID: UUID?

    func dropEntered(info: DropInfo) {
        dropTargetTabID = targetTab.id
    }

    func dropExited(info: DropInfo) {
        if dropTargetTabID == targetTab.id {
            dropTargetTabID = nil
        }
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.text])
    }

    func performDrop(info: DropInfo) -> Bool {
        dropTargetTabID = nil
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let idString = object as? String, let sourceID = UUID(uuidString: idString) else { return }
            DispatchQueue.main.async {
                appState.moveTab(id: sourceID, before: targetTab.id)
            }
        }
        return true
    }
}
