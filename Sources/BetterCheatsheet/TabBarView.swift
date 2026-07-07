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
    /// False in the overlay (see CheatsheetView) - reordering only makes
    /// sense in the main window, where it's actually meant to be a
    /// persistent organizational action. Without this, a tab's own
    /// `.highPriorityGesture` drag recognizer (below) intercepts every
    /// mouseDown on a tab before the overlay panel's own
    /// `isMovableByWindowBackground` gets a chance at it, so trying to drag
    /// the whole floating overlay by grabbing it over a tab looked "buggy" -
    /// it silently started an (unwanted, and pointless in a read-only
    /// overlay) tab-reorder drag instead of moving the window.
    var allowReordering: Bool = true
    /// Overlay-only: shows a pinned "..." button that opens the main editor
    /// window, since the overlay itself has no title bar/Dock icon to click.
    var onOpenMainWindow: (() -> Void)? = nil

    @State private var hoveredTabID: UUID?
    @State private var hoverWorkItem: DispatchWorkItem?
    @State private var isAddingTab = false
    @State private var newTabName = ""
    /// Which table template the pending "+" flow will create - set when the
    /// user picks an option from the popover, read once in `commitNewTab()`.
    @State private var pendingIsTrackpad = false
    /// True while the "+" button's template-choice popover is showing.
    @State private var isChoosingTemplate = false
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
            .onPreferenceChange(UUIDFramePreferenceKey<TabFrameTag>.self) { tabFrames = $0 }

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
                    key: UUIDFramePreferenceKey<TabFrameTag>.self,
                    value: [tab.id: geo.frame(in: .named(Self.dragSpace))]
                )
            }
        )
        .onHover { hovering in setHovered(tab, hovering: hovering) }
        // High priority (over TabButton's own tap gesture) but only
        // actually engages once the drag exceeds 8pt - a short click still
        // falls through untouched to select the tab. Unconditionally
        // attached (not wrapped in an `if allowReordering` branch) - an
        // earlier version of this fix did branch on it, which changed this
        // view's underlying type per-render (`_ConditionalContent`) and
        // broke in-flight drag tracking for real tab reordering in the main
        // window too (a three-finger-drag reorder no longer completed).
        // `including: allowReordering ? .all : .none` disables the gesture
        // via `GestureMask` instead - same modifier chain/view identity
        // every time, just inert in the overlay, where reordering
        // shouldn't happen anyway (see `allowReordering`'s doc comment) and
        // this gesture claiming the mouseDown first was blocking the
        // overlay panel's own `isMovableByWindowBackground` drag.
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
                },
            including: allowReordering ? .all : .none
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
            // The "+" now has two table templates to choose between (see
            // TabItem.isTrackpadTemplate) before it drops into the naming
            // text field below. A `.popover` (real NSPopover) presents the
            // two choices, rather than a SwiftUI `Menu` - kept the existing
            // TabBarIconButtonStyle look/pressed-feedback on the "+" itself
            // this way, and a popover with plain Buttons inside is simple
            // to reason about.
            Button {
                isChoosingTemplate = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(TabBarIconButtonStyle())
            .focusable(false)
            .help("Add tab")
            .popover(isPresented: $isChoosingTemplate, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    templateChoiceRow(title: "Keyboard Shortcut", systemImage: "keyboard", isTrackpad: false)
                    templateChoiceRow(title: "Trackpad Shortcut", systemImage: "hand.draw", isTrackpad: true)
                }
                // 10, not the row's own tighter 6, so the highlight (which
                // nearly spans this padding's full inset) reads as
                // concentric with the popover bubble's own large corner
                // radius, rather than a small-radius rectangle sitting
                // awkwardly close to a much rounder outer edge.
                .padding(10)
                .frame(width: 200)
            }
        }
    }

    /// A row in the "+" popover. Deliberately not a `Button` - AppKit gives a
    /// SwiftUI `Button` inside a popover its own focus ring (rendered in the
    /// app's accent color, which happens to be a yellow/gold here), and
    /// `.buttonStyle(.plain)` alone doesn't suppress it. A plain view with
    /// `.onTapGesture` (the same approach `TabButton` already uses for tab
    /// selection) has no button identity for AppKit to draw a focus ring
    /// around at all, and lets hover state show a background highlight
    /// (`isHovered`) matching this app's existing pill/row styling instead
    /// of relying on default system list-row appearance.
    private func templateChoiceRow(title: String, systemImage: String, isTrackpad: Bool) -> some View {
        TemplateChoiceRow(title: title, systemImage: systemImage) {
            isChoosingTemplate = false
            beginAddingTab(isTrackpad: isTrackpad)
        }
    }

    private func beginAddingTab(isTrackpad: Bool) {
        pendingIsTrackpad = isTrackpad
        newTabName = ""
        isAddingTab = true
    }

    /// Enter commits the name, creates the (table-format, one-empty-row)
    /// tab in whichever template was picked from the "+" dropdown, and hands
    /// off focus to that row's Shortcut field - see `pendingContentFocusTabID`
    /// and ShortcutTableView's `focusFirstRowOnAppear` - so naming a tab and
    /// starting to fill it in is one continuous flow with no extra click.
    private func commitNewTab() {
        let trimmed = newTabName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            withAnimation(.easeOut(duration: 0.25)) {
                appState.addTab(named: trimmed, isTrackpad: pendingIsTrackpad)
            }
            appState.pendingContentFocusTabID = appState.selectedTabID
        }
        newTabName = ""
        isAddingTab = false
    }
}

/// A single row in the "+" popover (see `templateChoiceRow`) - an icon, a
/// label, and a hover-highlighted background, with no `Button` involved so
/// there's no AppKit focus ring to suppress.
private struct TemplateChoiceRow: View {
    let title: String
    let systemImage: String
    var action: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            Text(title)
        }
        // Centered as a group within the full-width row, rather than
        // left-aligned with a trailing Spacer - the hover highlight below
        // spans the whole row width, so left-aligned content read as
        // stranded off to one side of it instead of sitting in the middle.
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            // 8 (not the tab bar's usual 6) - this row sits close to the
            // popover bubble's own much-larger corner radius (its 10pt
            // outer padding is the only gap between them), so a small,
            // tight radius here looked visually mismatched against that
            // big rounded bubble edge. A slightly bigger radius reads as
            // concentric with it instead.
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(perform: action)
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
        // A plain single .onTapGesture (no count:2 sibling) - having both a
        // count:1 and count:2 recognizer on the same view forces the system
        // to wait out the double-click window before committing to the
        // single-tap action, since it can't yet know a second tap won't
        // follow. That made every tab switch feel like it took "a second"
        // to register (real bug, fixed 2026-07-07). Double-click-to-rename
        // is gone as a result, but the context menu's "Rename" below already
        // covered the same action, so nothing is actually lost.
        .onTapGesture {
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
