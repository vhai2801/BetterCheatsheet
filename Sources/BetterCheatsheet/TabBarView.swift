import SwiftUI

/// Horizontal, scrollable tab bar. Tabs truncate their name when there are too
/// many to fit; hovering a tab smoothly expands it to show the full name.
/// No limit on tab count. Includes a "+" control to add new (table-format)
/// tabs and a separate button to add a freeform Note tab.
///
/// Reordering is driven purely by the drag's horizontal position, not by
/// hovering directly over another tab: a thin marker (`gapView`) sits
/// between every pair of tabs (and at both ends) right in the tab row
/// itself, so it's always exactly at a real tab boundary regardless of
/// individual tab widths - normally zero-width/invisible, it only expands
/// into a visible accent bar at whichever gap the drag currently targets.
/// Dropping anywhere (even far below the tab bar, e.g. over the window's
/// content area) commits to that gap. This avoids the old onDrag/onDrop
/// behavior, which only reacted once the cursor was precisely over another
/// tab's own bounds.
struct TabBarView: View {
    @ObservedObject var appState: AppState
    var allowAdding: Bool = true
    var showsSettingsTab: Bool = false
    /// Overlay-only: shows a pinned "..." button that opens the main editor
    /// window, since the overlay itself has no title bar/Dock icon to click.
    var onOpenMainWindow: (() -> Void)? = nil

    @State private var hoveredTabID: UUID?
    @State private var hoverWorkItem: DispatchWorkItem?
    @State private var isAddingTab = false
    @State private var newTabName = ""
    @FocusState private var isNewTabFieldFocused: Bool

    /// Each tab's on-screen frame, in the `dragSpace` coordinate space -
    /// recorded via a GeometryReader behind every tab so the drag gesture
    /// (attached separately) can tell which gap a given x-position falls in.
    @State private var tabFrames: [UUID: CGRect] = [:]
    @State private var draggingTabID: UUID?
    /// Captured once when the drag starts and held fixed for its duration -
    /// once the dragged tab collapses to zero width (see `tabButton(for:)`),
    /// its entry in `tabFrames` reflects that collapsed size instead, so the
    /// floating copy can't rely on it for its (pre-collapse) size/position.
    @State private var draggedTabOriginFrame: CGRect?
    @State private var dragTranslation: CGSize = .zero
    @State private var insertionIndex: Int?

    private static let dragSpace = "BetterCheatsheet.tabBarDrag"

    var body: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                // The insertion marker is a real (very thin) element living
                // right in this HStack alongside the tabs, rather than a
                // separately-positioned overlay computed from manual frame
                // math - so it's automatically always exactly at a tab
                // boundary, whatever width each individual tab happens to
                // be, with no coordinate math to get wrong.
                HStack(spacing: 4) {
                    gapView(at: 0)
                    // Every tab stays mounted here, including the one being
                    // dragged - its drag gesture lives on this exact view,
                    // so removing it from the tree mid-drag (e.g. via
                    // ForEach filtering) would kill the in-progress gesture.
                    // Collapsing its width to 0 instead still closes the gap
                    // visually without tearing down the view.
                    ForEach(Array(appState.tabs.enumerated()), id: \.element.id) { index, tab in
                        tabButton(for: tab)
                        gapView(at: index + 1)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .onPreferenceChange(TabFramePreferenceKey.self) { tabFrames = $0 }

            // Fixed outside the scroll view, alongside Settings, so neither
            // ever gets pushed out of view by tab overflow.
            if allowAdding {
                addTabControl

                addNoteTabButton
                    .padding(.trailing, 8)
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
        // Named on the whole row (not just the scrollable content) so the
        // floating drag-preview overlay below - which lives outside the
        // ScrollView specifically to avoid being clipped to its height -
        // still shares the same coordinate system as the tab frames.
        .coordinateSpace(name: Self.dragSpace)
        .frame(height: 34)
        .background(.thinMaterial)
        .overlay(alignment: .topLeading) {
            if let draggingTabID, let tab = appState.tabs.first(where: { $0.id == draggingTabID }),
               let frame = draggedTabOriginFrame {
                floatingTab(tab, at: frame)
            }
        }
    }

    /// Always creates a brand new freeform Note tab rather than converting an
    /// existing one - so there's no toggle anywhere that could accidentally
    /// flip a tab someone already filled in as a table (or vice versa).
    private var addNoteTabButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.25)) {
                appState.addNoteTab()
            }
        } label: {
            Image(systemName: "note.text")
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help("New note tab")
    }

    private func openMainWindowButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "ellipsis")
                .font(.system(size: 14))
        }
        // TabBarIconButtonStyle's padding is part of the button's label, so
        // (unlike plain .buttonStyle(.plain)) the whole padded square is
        // clickable, not just the glyph's own tight bounds.
        .buttonStyle(TabBarIconButtonStyle())
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
            onSelect: { selectTab(tab) },
            onRename: { renameTab(tab, to: $0) },
            onDelete: { appState.deleteTab(id: tab.id) }
        )
        // Slides in from the trailing edge when newly added (see
        // commitNewTab/addNoteTabButton, which wrap tab creation in
        // withAnimation) - cheap since it's just the one new view.
        .transition(.move(edge: .trailing).combined(with: .opacity))
        // Collapsed (not removed - see the ForEach above) while dragging, so
        // neighboring tabs close the gap; the floating copy in the overlay
        // is what's actually visible during the drag.
        .frame(width: draggingTabID == tab.id ? 0 : nil)
        .opacity(draggingTabID == tab.id ? 0 : 1)
        .clipped()
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: TabFramePreferenceKey.self,
                    value: [tab.id: geo.frame(in: .named(Self.dragSpace))]
                )
            }
        )
        .onHover { hovering in setHovered(tab, hovering: hovering) }
        // High priority (over TabButton's own tap/double-tap gestures) but
        // only actually engages once the drag exceeds 8pt - short clicks and
        // double-clicks (select/rename) fall through untouched.
        .highPriorityGesture(
            DragGesture(minimumDistance: 8, coordinateSpace: .named(Self.dragSpace))
                .onChanged { value in
                    if draggingTabID != tab.id {
                        draggingTabID = tab.id
                        draggedTabOriginFrame = tabFrames[tab.id]
                        hoveredTabID = nil
                    }
                    dragTranslation = value.translation
                    updateInsertionIndex(forX: value.location.x, draggingID: tab.id)
                }
                .onEnded { _ in
                    commitReorder()
                }
        )
    }

    /// A non-interactive duplicate of the dragged tab, positioned at its
    /// original spot plus however far the drag has moved - this is what
    /// visibly follows the cursor, while the real tab in the HStack is
    /// hidden (see `tabButton(for:)`) so it isn't drawn twice.
    private func floatingTab(_ tab: TabItem, at frame: CGRect) -> some View {
        TabButton(
            tab: tab,
            isSelected: tab.id == appState.selectedTabID,
            isHovered: false,
            onSelect: {},
            onRename: { _ in },
            onDelete: {}
        )
        .frame(width: frame.width, height: frame.height)
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        .position(x: frame.midX + dragTranslation.width, y: frame.midY + dragTranslation.height)
        .allowsHitTesting(false)
    }

    /// Which gap between tabs `x` currently falls in, skipping the tab being
    /// dragged itself - not restricted to `x` actually landing inside the
    /// tab bar's own bounds, so dragging far below it (anywhere in the
    /// window) still tracks the nearest gap by horizontal position alone.
    private func updateInsertionIndex(forX x: CGFloat, draggingID: UUID) {
        let orderedIDs = appState.tabs.map(\.id)
        var newIndex = orderedIDs.count
        for (i, id) in orderedIDs.enumerated() {
            guard id != draggingID, let frame = tabFrames[id] else { continue }
            if x < frame.midX {
                newIndex = i
                break
            }
        }
        insertionIndex = newIndex
    }

    private func commitReorder() {
        if let draggingTabID, let insertionIndex {
            appState.moveTab(id: draggingTabID, toIndex: insertionIndex)
        }
        draggingTabID = nil
        draggedTabOriginFrame = nil
        dragTranslation = .zero
        insertionIndex = nil
    }

    /// A thin marker living directly in the tab row at position `index`
    /// (before tab `index` in `appState.tabs`, or at the very end if
    /// `index == appState.tabs.count`). Reserves zero width normally, so it
    /// adds no extra spacing to the everyday tab layout - it only takes up
    /// room (and turns into a visible accent-colored bar) when it's the
    /// active drop target of an in-progress drag.
    private func gapView(at index: Int) -> some View {
        let isActive = draggingTabID != nil && insertionIndex == index
        return Capsule()
            .fill(Color.accentColor)
            .frame(width: 3, height: 22)
            .frame(width: isActive ? 7 : 0)
            .opacity(isActive ? 1 : 0)
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.12), value: insertionIndex)
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
        // Otherwise the cursor (or the floating drag preview) sweeping over
        // neighboring tabs while reordering would keep expanding them past
        // their normal capped width, fighting the reorder animation.
        guard draggingTabID == nil else { return }
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
            // Styled like a real TabButton pill (same padding/background/
            // border) and grows with the typed name via fixedSize, rather
            // than sitting in a plain fixed-width box - so it reads as "the
            // tab you're about to create" instead of a generic text field.
            TextField("Tab name", text: $newTabName)
                .textFieldStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(minWidth: 60, alignment: .leading)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.accentColor.opacity(0.6), lineWidth: 1)
                )
                .focused($isNewTabFieldFocused)
                .onAppear {
                    // A same-tick assignment here routinely loses the race
                    // and leaves the field visible but not actually focused
                    // (confirmed via accessibility inspection: `focused`
                    // reported false immediately after appearing) - deferring
                    // one tick lets this transaction finish first.
                    DispatchQueue.main.async { isNewTabFieldFocused = true }
                }
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
            .buttonStyle(TabBarIconButtonStyle())
            .focusable(false)
            .help("Add tab")
        }
    }

    /// Enter commits the name, creates the (table-format, one-empty-row)
    /// tab, and hands off focus to that row's Shortcut field - see
    /// `pendingContentFocusTabID` and ShortcutTableView's
    /// `focusFirstRowOnAppear` - so naming a tab and starting to fill it in
    /// is one continuous flow with no extra click.
    private func commitNewTab() {
        let trimmed = newTabName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            withAnimation(.easeOut(duration: 0.25)) {
                appState.addTab(named: trimmed)
            }
            appState.pendingContentFocusTabID = appState.selectedTabID
        }
        newTabName = ""
        isAddingTab = false
    }
}

/// Gives icon-only tab bar buttons (the "+" control) a visible pressed
/// state - `.buttonStyle(.plain)` alone leaves clicks with no feedback at
/// all beyond whatever action they trigger.
private struct TabBarIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    // Never truly alpha-0, even at rest: the overlay panel
                    // has isMovableByWindowBackground = true, and AppKit
                    // decides "drag the window" vs. "hit the control" by
                    // testing the actual rendered alpha at the click point -
                    // a fully transparent Color.clear fill gets treated as
                    // window background, so clicks around the icon (but not
                    // exactly on its opaque pixels) started a window-drag
                    // instead of reaching the button. 0.02 is far above the
                    // 8-bit rounding floor (~1/255) so it always renders as a
                    // nonzero-alpha pixel, but is visually indistinguishable
                    // from fully clear.
                    .fill(configuration.isPressed ? Color.primary.opacity(0.15) : Color.primary.opacity(0.02))
            )
    }
}

private struct TabFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
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
                    isSelected ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.2),
                    lineWidth: 1
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
