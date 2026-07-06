import SwiftUI

/// Horizontal, scrollable tab bar. Tabs truncate their name when there are too
/// many to fit; hovering a tab smoothly expands it to show the full name.
/// No limit on tab count. Includes a "+" control to add new tabs.
struct TabBarView: View {
    @ObservedObject var appState: AppState
    var allowAdding: Bool = true
    var showsSettingsTab: Bool = false

    @State private var hoveredTabID: UUID?
    @State private var isAddingTab = false
    @State private var newTabName = ""

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(appState.tabs) { tab in
                    tabButton(for: tab)
                }

                if allowAdding {
                    addTabControl
                }

                if showsSettingsTab {
                    SettingsTabButton(isSelected: appState.isShowingSettings, onSelect: selectSettings)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .frame(height: 34)
        .background(.thinMaterial)
    }

    @ViewBuilder
    private func tabButton(for tab: TabItem) -> some View {
        TabButton(
            tab: tab,
            isSelected: tab.id == appState.selectedTabID,
            isHovered: hoveredTabID == tab.id,
            onSelect: { selectTab(tab) },
            onRename: { renameTab(tab, to: $0) },
            onDelete: { appState.deleteTab(id: tab.id) }
        )
        .onHover { hovering in setHovered(tab, hovering: hovering) }
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

    private func setHovered(_ tab: TabItem, hovering: Bool) {
        if hovering {
            hoveredTabID = tab.id
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
                .onSubmit { commitNewTab() }
                .onExitCommand { isAddingTab = false; newTabName = "" }
        } else {
            Button {
                newTabName = ""
                isAddingTab = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
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
    var onSelect: () -> Void
    var onRename: (String) -> Void
    var onDelete: () -> Void

    @State private var isRenaming = false
    @State private var draftName = ""

    var body: some View {
        Group {
            if isRenaming {
                TextField("Tab name", text: $draftName)
                    .textFieldStyle(.plain)
                    .frame(minWidth: 60)
                    .onSubmit { commitRename() }
                    .onExitCommand { isRenaming = false }
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

private struct SettingsTabButton: View {
    let isSelected: Bool
    var onSelect: () -> Void

    var body: some View {
        Label("Settings", systemImage: "gearshape")
            .labelStyle(.titleAndIcon)
            .font(.system(size: 12))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
    }
}
