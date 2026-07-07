import AppKit
import SwiftUI

/// Two-column (Shortcut, Action) table used by tabs that aren't flagged as a
/// freeform "Note tab" - keeps every such tab visually consistent instead of
/// freeform rich text. Built with `Grid` rather than a fixed-size layout so
/// it degrades gracefully as the overlay is resized: the shortcut column
/// keeps a minimum width and the action column wraps text instead of
/// clipping or overflowing the panel.
struct ShortcutTableView: View {
    @Binding var rows: [ShortcutRow]
    var isEditable: Bool
    /// Column width/inset live here (see Settings.swift) rather than as
    /// local @State, for two reasons: they need to survive EditorView
    /// force-remounting this view on every tab switch (`.id(tab.id)`), and
    /// the main window and overlay - two separate ShortcutTableView
    /// instances - should show the same column layout, not independent ones.
    @ObservedObject var settings: SettingsStore
    /// True right after this tab was created via the tab bar's "+" flow -
    /// jumps straight into the first row's Shortcut field on appearing, so
    /// naming the tab and filling in its first entry is one uninterrupted
    /// flow. `onFocusRequestHandled` lets the caller reset the tab-level
    /// flag that drives this so it doesn't refire on every tab switch.
    var focusFirstRowOnAppear: Bool = false
    var onFocusRequestHandled: () -> Void = {}

    /// Which row's Shortcut field should take focus next - set when Tab in
    /// the last row's Action field appends a new row, so typing can continue
    /// straight into it without reaching for the mouse.
    @FocusState private var focusedRowID: UUID?

    private let actionColumnMinWidth: CGFloat = 120
    private let deleteButtonWidth: CGFloat = 20

    /// Explicit width for the Action column, computed to fill whatever
    /// space is actually left in the ScrollView's own viewport
    /// (`scrollViewWidth`, see below) after every other fixed-width
    /// neighbor - so the delete button ends up pinned near the window's
    /// trailing edge (like the native scrollbar) instead of hugging
    /// whatever narrow width Action's own content happened to need.
    /// `.frame(width:)` (not `minWidth:`) is what makes this actually
    /// stretch the column - Grid still reports the Grid's own natural
    /// size to the outer `.fixedSize(horizontal: true, ...)`, but that
    /// natural size now already includes this larger, explicitly-set
    /// width, so nothing overrides it. Grid sizes a column to the widest
    /// cell in it across every row, so leaving the *header's* "Action"
    /// text unconstrained is fine - it just renders left-aligned within
    /// whatever width the data rows establish.
    private var actionColumnWidth: CGFloat {
        let outerPadding: CGFloat = 24 // the Group's .padding(12), both sides
        let gridSpacing: CGFloat = 12 // Grid's horizontalSpacing, once per gap between cells
        let shortcutCellWidth = shortcutColumnWidth + 9 // box + its trailing handle/placeholder
        var reserved = outerPadding + shortcutCellWidth + gridSpacing
        if isEditable {
            reserved += 16 + gridSpacing // grip column + the gap before Shortcut
            reserved += gridSpacing + deleteButtonWidth // the gap before, and the delete button itself
        }
        return max(actionColumnMinWidth, scrollViewWidth - reserved)
    }

    /// Live-drag overrides for the two column resize handles below - kept
    /// separate from the persisted settings values so a resize in progress
    /// doesn't write to disk on every pixel of movement; the persisted
    /// value is only updated once, in the drag's `onEnded`. The handles use
    /// the drag's translation (a delta from where the drag started), not its
    /// absolute position, so `dragStart...` snapshots the pre-drag value once
    /// per drag to add that delta to.
    @State private var liveShortcutColumnWidth: CGFloat?
    @State private var liveShortcutColumnLeadingInset: CGFloat?
    @State private var dragStartColumnWidth: CGFloat = 0
    @State private var dragStartLeadingInset: CGFloat = 0

    private var shortcutColumnWidth: CGFloat {
        liveShortcutColumnWidth ?? settings.shortcutColumnWidth
    }
    private var shortcutColumnLeadingInset: CGFloat {
        liveShortcutColumnLeadingInset ?? settings.shortcutColumnLeadingInset
    }

    /// Row drag-to-reorder state - same gap-based design as TabBarView's tab
    /// reordering (track each row's frame, find which gap the drag's Y
    /// position falls in, commit on release), just tracking vertical
    /// position instead of horizontal. The resting (non-dragging) row
    /// separators are NOT drawn inside the Grid - see `separatorOverlay` -
    /// only the accent-colored active drop indicator lives in-grid.
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var gripFrames: [UUID: CGRect] = [:]
    @State private var headerFrame: CGRect = .zero
    /// The ScrollView's own width - tracked explicitly (background +
    /// PreferenceKey, same pattern as headerFrame/rowFrames) rather than
    /// read from a GeometryReader placed directly as the separator
    /// overlay's own content, which was reporting a size matching the
    /// Grid's own (now narrow, fixed-size) natural width instead of the
    /// true ScrollView viewport - the actual cause of the separator lines
    /// stopping partway across instead of reaching the trailing edge.
    @State private var scrollViewWidth: CGFloat = 0
    @State private var draggingRowID: UUID?
    @State private var draggedRowOriginFrame: CGRect?
    @State private var draggedGripOriginFrame: CGRect?
    @State private var dragTranslation: CGFloat = 0
    @State private var insertionIndex: Int?

    private static let rowDragSpace = "BetterCheatsheet.rowDrag"

    var body: some View {
        ScrollView {
            // Wrapping the whole content in this frame (rather than
            // applying it to the ScrollView itself, from outside) makes the
            // ScrollView's actual document view - what the underlying
            // AppKit NSScrollView scrolls and positions its native scroller
            // against - genuinely wide, not just SwiftUI's own layout
            // frame for the ScrollView. Widening only the ScrollView from
            // outside fixed the separator lines (a SwiftUI-level
            // GeometryReader measurement) but left the real scrollbar still
            // glued to the narrow Grid's trailing edge instead of the
            // window's true edge.
            Group {
                if rows.isEmpty {
                    Text(isEditable ? "No shortcuts yet - add one below" : "No shortcuts yet")
                        .foregroundStyle(.secondary)
                        .padding(12)
                } else {
                    Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        if isEditable {
                            Color.clear.frame(width: 16, height: 1)
                        }
                        shortcutColumnCell(showsHandles: isEditable) { Text("Shortcut") }
                        // The GeometryReader/preference lives on this one
                        // cell specifically, not chained after the GridRow
                        // itself - a modifier chained onto a GridRow is
                        // broadcast to every cell in the row individually
                        // (a Grid quirk), so attaching it to the row was
                        // giving every cell, including the 1pt-tall trailing
                        // spacer below, its own competing measurement; the
                        // spacer's tiny frame - being the last one written -
                        // was the one HeaderFramePreferenceKey ended up
                        // with, placing the separator across the middle of
                        // the header text instead of below it.
                        Text("Action")
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: HeaderFramePreferenceKey.self,
                                        value: geo.frame(in: .named(Self.rowDragSpace))
                                    )
                                }
                            )
                        if isEditable {
                            Color.clear.frame(width: 16, height: 1)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    gapView(at: 0)

                    ForEach($rows) { $row in
                        let index = rows.firstIndex(where: { $0.id == row.id }) ?? 0
                        let isLastRow = index == rows.count - 1

                        GridRow {
                            if isEditable {
                                gripHandle(for: row.id)
                            }

                            shortcutColumnCell(showsHandles: false) {
                                if isEditable {
                                    ShortcutTableTextField(text: $row.shortcut, capturesModifierKeys: true)
                                        .modifier(FocusIfNeeded(focusedRowID: $focusedRowID, rowID: row.id))
                                } else {
                                    Text(row.shortcut)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .textSelection(.enabled)
                                }
                            }

                            cell(
                                for: $row.action,
                                rowID: nil,
                                width: actionColumnWidth,
                                // Nothing to tab to after the last row's
                                // Action field - append a new row instead of
                                // just leaving the table.
                                onTab: isLastRow ? {
                                    let newRow = ShortcutRow()
                                    rows.append(newRow)
                                    focusedRowID = newRow.id
                                } : nil
                            )

                            if isEditable {
                                Button {
                                    rows.removeAll { $0.id == row.id }
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.plain)
                                .focusable(false)
                                .foregroundStyle(.secondary)
                                .frame(width: deleteButtonWidth)
                            }
                        }
                        // Collapsed (not removed) while dragging so the grip
                        // handle's own drag gesture isn't torn down
                        // mid-drag - the floating copy is what's visible.
                        .frame(height: draggingRowID == row.id ? 0 : nil)
                        .opacity(draggingRowID == row.id ? 0 : 1)
                        .clipped()
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: RowFramePreferenceKey.self,
                                    value: [row.id: geo.frame(in: .named(Self.rowDragSpace))]
                                )
                            }
                        )

                        gapView(at: index + 1)
                    }
                }
                .padding(12)
                // Forces the Grid to report/use its own natural (sum of
                // column widths) size horizontally, rather than stretching
                // to whatever width the ScrollView happens to make
                // available - otherwise a narrow Shortcut column setting
                // was being visually overridden by the container's width.
                .fixedSize(horizontal: true, vertical: false)
                }
            }
            // The Grid's own .fixedSize above keeps its columns narrow, but
            // without this the ScrollView's document view also shrinks to
            // match that narrow content instead of filling whatever width
            // its parent actually gives it - which was the real reason
            // both the separator lines and the native scrollbar stopped
            // well short of the window's true edge instead of reaching it.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: ScrollViewWidthPreferenceKey.self, value: proxy.size.width)
            }
        )
        .coordinateSpace(name: Self.rowDragSpace)
        .onPreferenceChange(RowFramePreferenceKey.self) { rowFrames = $0 }
        .onPreferenceChange(GripFramePreferenceKey.self) { gripFrames = $0 }
        .onPreferenceChange(HeaderFramePreferenceKey.self) { headerFrame = $0 }
        .onPreferenceChange(ScrollViewWidthPreferenceKey.self) { scrollViewWidth = $0 }
        .overlay(alignment: .topLeading) {
            separatorOverlay
            if let draggingRowID, let row = rows.first(where: { $0.id == draggingRowID }),
               let gripFrame = draggedGripOriginFrame {
                floatingShortcutBadge(row, near: gripFrame)
            }
        }
        .onAppear {
            applyPendingFocusIfNeeded(shouldFocus: focusFirstRowOnAppear)
        }
        .onChange(of: focusFirstRowOnAppear) { newValue in
            applyPendingFocusIfNeeded(shouldFocus: newValue)
        }
    }

    /// A small drag handle - dragging the whole row would fight the text
    /// fields' own click-to-place-cursor behavior, so only this handle
    /// carries the reorder gesture. minimumDistance keeps a plain click from
    /// starting a drag. Tracks its own frame separately from the row's (see
    /// GripFramePreferenceKey) so the floating preview can stay anchored
    /// near the handle instead of centered across the whole (potentially
    /// very wide, thanks to the Action column) row.
    private func gripHandle(for rowID: UUID) -> some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .frame(width: 16, height: 20)
            .contentShape(Rectangle())
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: GripFramePreferenceKey.self,
                        value: [rowID: geo.frame(in: .named(Self.rowDragSpace))]
                    )
                }
            )
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.rowDragSpace))
                    .onChanged { value in
                        if draggingRowID != rowID {
                            draggingRowID = rowID
                            draggedRowOriginFrame = rowFrames[rowID]
                            draggedGripOriginFrame = gripFrames[rowID]
                        }
                        dragTranslation = value.translation.height
                        updateInsertionIndex(forY: value.location.y, draggingID: rowID)
                    }
                    .onEnded { _ in commitReorder() }
            )
    }

    /// Wraps the Shortcut column's content (the header label, or a row's
    /// field/text) so header and every row share identical sizing - and,
    /// only for the header of an editable (main window) instance
    /// (`showsHandles`, gated on `isEditable`), book-ends it with two
    /// visible resize handles. The overlay's own column width/inset are
    /// still fully live - it reads the same shared SettingsStore - it just
    /// can't be dragged from there; resizing is main-window-only. The
    /// leading handle sits *inside* the same padded box as the label,
    /// immediately before it, so increasing the inset pushes both of them
    /// right together - the handle visually tracks alongside "Shortcut"
    /// instead of staying pinned at the column's outer edge while only the
    /// text moves. The trailing handle sits outside the box, right after
    /// it, so it moves with the box's own width instead. Rows reserve the
    /// same leading width the handle would occupy (a clear spacer instead
    /// of the handle itself) - without it, "Shortcut" sat 13pt further
    /// right than every row's actual value, since only the header had
    /// something occupying that space before its label.
    @ViewBuilder
    private func shortcutColumnCell<Content: View>(showsHandles: Bool, @ViewBuilder content: () -> Content) -> some View {
        // 12, not 4, to match the Grid's own horizontalSpacing (see the
        // Grid initializer above) - the trailing handle's gap to "Action"
        // comes from that Grid spacing, so the leading handle's gap to
        // "Shortcut" needs the same value to look symmetric.
        let box = HStack(spacing: 12) {
            if showsHandles {
                leadingInsetHandle
            } else {
                Color.clear.frame(width: 9)
            }
            content()
        }
        .padding(.leading, shortcutColumnLeadingInset)
        .frame(width: shortcutColumnWidth, alignment: .leading)

        HStack(spacing: 0) {
            box
            if showsHandles {
                columnWidthHandle
            } else {
                Color.clear.frame(width: 9)
            }
        }
    }

    /// Dragging this (at the Shortcut column's left edge) pushes the text
    /// further in without changing the column's own width - "the cmd
    /// letters starting further in."
    private var leadingInsetHandle: some View {
        columnResizeHandle {
            if liveShortcutColumnLeadingInset == nil {
                dragStartLeadingInset = settings.shortcutColumnLeadingInset
            }
        } onDrag: { translationWidth in
            let newInset = dragStartLeadingInset + translationWidth
            liveShortcutColumnLeadingInset = min(max(newInset, 0), max(shortcutColumnWidth - 24, 0))
        } onEnded: {
            if let liveShortcutColumnLeadingInset {
                settings.shortcutColumnLeadingInset = liveShortcutColumnLeadingInset
            }
            liveShortcutColumnLeadingInset = nil
        }
    }

    /// Dragging this (at the boundary between Shortcut and Action) changes
    /// the Shortcut column's width - "the action column closer to the
    /// shortcut column" when dragged left, further away when dragged right.
    private var columnWidthHandle: some View {
        columnResizeHandle {
            if liveShortcutColumnWidth == nil {
                dragStartColumnWidth = settings.shortcutColumnWidth
            }
        } onDrag: { translationWidth in
            let newWidth = dragStartColumnWidth + translationWidth
            liveShortcutColumnWidth = min(max(newWidth, 50), 400)
        } onEnded: {
            if let liveShortcutColumnWidth {
                settings.shortcutColumnWidth = liveShortcutColumnWidth
            }
            liveShortcutColumnWidth = nil
        }
    }

    /// A visible (if faint) vertical divider with a wider hit target around
    /// it, so it's actually discoverable instead of a purely invisible strip
    /// you'd have to already know the location of. Uses the drag's
    /// translation (relative to where the drag started) rather than its
    /// absolute position, so it needs no coordinate-space/frame tracking at
    /// all - just a plain, default-space DragGesture.
    private func columnResizeHandle(
        onDragStart: @escaping () -> Void,
        onDrag: @escaping (CGFloat) -> Void,
        onEnded: @escaping () -> Void
    ) -> some View {
        ZStack {
            // The overlay panel has isMovableByWindowBackground = true, and
            // AppKit decides "drag the window" vs. "hit the control" by the
            // actual rendered alpha at the click point (same underlying
            // issue as the overlay's "..." button, see TabBarView) - a
            // fully transparent hit target outside the thin visible line
            // was being treated as window background, so the whole panel
            // dragged instead of resizing the column. This fill, covering
            // the *entire* hit width (not just the visible line), keeps
            // every pixel of it non-zero alpha.
            Rectangle()
                .fill(Color.primary.opacity(0.02))
            Rectangle()
                .fill(Color.primary.opacity(0.15))
                .frame(width: 1)
        }
        .frame(width: 9)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            // onDragStart is called on every change, but each caller only
            // acts the first time (guarding on its own live-value still
            // being nil) - simpler than this shared helper trying to know
            // which of the two live values belongs to it.
            //
            // Named coordinate space (not the default .local) is required
            // here, not optional: the right-hand handle sits right after
            // the content whose width it drags, so its own position shifts
            // as a direct side effect of the very drag it's tracking. With
            // .local, translation is measured against that same shifting
            // frame, feeding back into itself - the handle read as "stuck"
            // and jittery. Measuring against the outer ScrollView's frame
            // instead (stable throughout the drag) fixes both.
            DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.rowDragSpace))
                .onChanged { value in
                    onDragStart()
                    onDrag(value.translation.width)
                }
                .onEnded { _ in onEnded() }
        )
    }

    /// A small floating badge showing just the Shortcut text, anchored next
    /// to the grip handle (not centered across the whole row, which - with
    /// a wide Action column - made the preview appear to "jump" away from
    /// the handle toward the row's far end) and following the cursor
    /// vertically only (rows reorder top-to-bottom, so horizontal cursor
    /// jitter is ignored).
    private func floatingShortcutBadge(_ row: ShortcutRow, near gripFrame: CGRect) -> some View {
        Text(row.shortcut.isEmpty ? "—" : row.shortcut)
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                    )
            )
            .fixedSize()
            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            .position(x: gripFrame.midX + 24, y: gripFrame.midY + dragTranslation)
            .allowsHitTesting(false)
    }

    /// Which gap between rows `y` currently falls in, skipping the row being
    /// dragged itself - same convention as TabBarView's horizontal version.
    private func updateInsertionIndex(forY y: CGFloat, draggingID: UUID) {
        let orderedIDs = rows.map(\.id)
        var newIndex = orderedIDs.count
        for (i, id) in orderedIDs.enumerated() {
            guard id != draggingID, let frame = rowFrames[id] else { continue }
            if y < frame.midY {
                newIndex = i
                break
            }
        }
        insertionIndex = newIndex
    }

    private func commitReorder() {
        if let draggingRowID, let insertionIndex {
            moveRow(id: draggingRowID, toIndex: insertionIndex)
        }
        draggingRowID = nil
        draggedRowOriginFrame = nil
        draggedGripOriginFrame = nil
        dragTranslation = 0
        insertionIndex = nil
    }

    /// Same convention as AppState.moveTab(id:toIndex:): `targetIndex` is a
    /// position in the *current* ordering, as if the row were removed first.
    private func moveRow(id: UUID, toIndex targetIndex: Int) {
        guard let sourceIndex = rows.firstIndex(where: { $0.id == id }) else { return }
        var insertAt = targetIndex
        if sourceIndex < insertAt { insertAt -= 1 }
        insertAt = min(max(insertAt, 0), rows.count)
        let item = rows.remove(at: sourceIndex)
        rows.insert(item, at: insertAt)
    }

    /// A gap at position `index` (before row `index`, or at the very end
    /// when `index == rows.count`). The resting dim separator line itself
    /// is NOT drawn here anymore (see `separatorOverlay`) - inside the
    /// Grid, a full-width-seeking line forces Grid to inflate the column
    /// track it spans to match (the same mechanism that was inflating the
    /// Shortcut column - see the Grid's `.fixedSize` above), so a resting
    /// separator that's actually supposed to span the *whole panel* can't
    /// live in-grid at all. This still reserves the gap and renders the
    /// bold accent-colored drop indicator when it's the current drag target.
    private func gapView(at index: Int) -> some View {
        let isActive = draggingRowID != nil && insertionIndex == index
        return Group {
            if isActive {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(height: 3)
            } else {
                Color.clear.frame(height: 1)
            }
        }
        .gridCellColumns(isEditable ? 4 : 2)
        .animation(.easeOut(duration: 0.12), value: insertionIndex)
    }

    /// Full-width (edge-to-edge of the panel, not just the table's columns)
    /// resting separator lines, drawn *outside* the fixed-size Grid - one
    /// just below the header, one between each pair of rows. Width comes
    /// from `scrollViewWidth` (tracked via background+PreferenceKey on the
    /// ScrollView itself), not a GeometryReader placed directly as this
    /// overlay's own content - that reported the Grid's own narrow natural
    /// width instead of the true viewport width, so lines stopped partway
    /// across rather than reaching the trailing edge. Y positions come from
    /// the same row/header frame tracking used for drag-to-reorder, so
    /// these also stay correctly placed as the window is resized.
    private var separatorOverlay: some View {
        let orderedFrames = rows.compactMap { rowFrames[$0.id] }
        let ys = separatorYPositions(orderedFrames: orderedFrames)
        return ForEach(Array(ys.enumerated()), id: \.offset) { _, y in
            Rectangle()
                .fill(Color.primary.opacity(0.15))
                .frame(width: scrollViewWidth, height: 1)
                .position(x: scrollViewWidth / 2, y: y)
        }
        .allowsHitTesting(false)
    }

    /// Y positions (in the shared rowDragSpace) for each resting separator:
    /// just below the header, and at the midpoint of the gap between every
    /// pair of consecutive rows. Skipped entirely if frames haven't been
    /// measured yet (headerFrame still `.zero`), rather than guessing.
    private func separatorYPositions(orderedFrames: [CGRect]) -> [CGFloat] {
        guard headerFrame != .zero else { return [] }
        var ys: [CGFloat] = [headerFrame.maxY + 4]
        if orderedFrames.count > 1 {
            for i in 1..<orderedFrames.count {
                ys.append((orderedFrames[i - 1].maxY + orderedFrames[i].minY) / 2)
            }
        }
        return ys
    }

    /// Called both from `onAppear` (the common case: the view mounts after
    /// `focusFirstRowOnAppear` is already true) and `onChange` (a fallback
    /// for when it only becomes true on a later render pass than the one
    /// that mounted this view, since `tabs`/`selectedTabID`/
    /// `pendingContentFocusTabID` are three separate @Published writes that
    /// don't necessarily land in the same SwiftUI update cycle). Takes the
    /// value explicitly rather than reading `self.focusFirstRowOnAppear` -
    /// `onChange`'s closure can see a stale snapshot of `self` where that
    /// property still reads the old value, even though its own `newValue`
    /// parameter correctly already reports the new one.
    private func applyPendingFocusIfNeeded(shouldFocus: Bool) {
        guard shouldFocus, let firstID = rows.first?.id else { return }
        DispatchQueue.main.async {
            focusedRowID = firstID
            onFocusRequestHandled()
        }
    }

    /// `width` (fixed) is used for the Shortcut column, whose size is
    /// user-adjustable; `minWidth` (flexible, grows with content) is used
    /// for the Action column, which isn't independently resizable - only
    /// its left edge, which is actually the Shortcut column's right edge.
    @ViewBuilder
    private func cell(
        for text: Binding<String>,
        rowID: UUID?,
        minWidth: CGFloat? = nil,
        width: CGFloat? = nil,
        leadingInset: CGFloat = 0,
        onTab: (() -> Void)? = nil,
        capturesModifierKeys: Bool = false
    ) -> some View {
        Group {
            if isEditable {
                ShortcutTableTextField(text: text, onTab: onTab, capturesModifierKeys: capturesModifierKeys)
                    .modifier(FocusIfNeeded(focusedRowID: $focusedRowID, rowID: rowID))
            } else {
                Text(text.wrappedValue)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(.leading, leadingInset)
        .modifier(CellWidthModifier(width: width, minWidth: minWidth))
    }
}

/// `.frame(width:)` and `.frame(minWidth:)` are different overloads that
/// can't both be passed in one call - this picks the right one based on
/// which was supplied.
private struct CellWidthModifier: ViewModifier {
    var width: CGFloat?
    var minWidth: CGFloat?

    func body(content: Content) -> some View {
        if let width {
            content.frame(width: width, alignment: .leading)
        } else {
            content.frame(minWidth: minWidth ?? 0, alignment: .leading)
        }
    }
}

private struct RowFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct GripFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct HeaderFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    /// Unconditionally taking nextValue() would let every other row (which
    /// never sets this key at all, contributing the .zero default as this
    /// preference bubbles up through them) stomp the header's real,
    /// already-measured value as soon as it's processed afterward - unlike
    /// the dictionary-based frame keys, where merging in an empty `[:]`
    /// default is harmless. Only overwrite with an actual measurement.
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

private struct ScrollViewWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next != 0 {
            value = next
        }
    }
}

/// Only the Shortcut column needs to be focus-targetable (to jump into the
/// newly-added row after Tab); this no-ops for the Action column (`rowID == nil`).
private struct FocusIfNeeded: ViewModifier {
    var focusedRowID: FocusState<UUID?>.Binding
    var rowID: UUID?

    func body(content: Content) -> some View {
        if let rowID {
            content.focused(focusedRowID, equals: rowID)
        } else {
            content
        }
    }
}

/// A plain single-line NSTextField used for every table cell. SwiftUI's
/// TextField has no way on macOS 13 to intercept individual keystrokes or
/// Tab, so this wraps NSTextField directly to get both:
/// - the same ALL-CAPS -> symbol auto-replace as the rich-text editor
///   (TextReplacement), applied reactively after each keystroke since
///   NSTextFieldDelegate (unlike NSTextViewDelegate) has no pre-change hook
/// - an optional Tab interception (see `onTab`), used only on the last row's
///   Action field to append a new row instead of tabbing off into nothing
/// - (Shortcut column only, `capturesModifierKeys`) inserting a modifier's
///   own symbol the instant it's physically pressed, so "⇧⌘K" can be typed
///   by literally holding Shift+Cmd+K instead of spelling out "SHIFT" etc.
private struct ShortcutTableTextField: NSViewRepresentable {
    @Binding var text: String
    var onTab: (() -> Void)?
    var capturesModifierKeys: Bool = false

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = context.coordinator
        if capturesModifierKeys {
            context.coordinator.startObservingModifierKeys(for: field)
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ShortcutTableTextField
        private weak var field: NSTextField?
        private var flagsMonitor: Any?
        private var heldModifierFlags: NSEvent.ModifierFlags = []

        private static let modifierSymbols: [(flag: NSEvent.ModifierFlags, symbol: String)] = [
            (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘"),
        ]

        init(_ parent: ShortcutTableTextField) {
            self.parent = parent
        }

        deinit {
            if let flagsMonitor {
                NSEvent.removeMonitor(flagsMonitor)
            }
        }

        func startObservingModifierKeys(for field: NSTextField) {
            self.field = field
            flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.handleFlagsChanged(event)
                return event
            }
        }

        /// Only reacts while this exact field is the one being edited
        /// (`currentEditor() != nil` - a plain NSTextField's field editor
        /// doesn't reliably route flagsChanged back through the field
        /// itself via the responder chain, hence a local monitor rather than
        /// overriding `flagsChanged` the way KeyRecorderNSView does), and
        /// only on a fresh press (a flag turning on that wasn't already
        /// held) - not on release, and not while it's already held.
        private func handleFlagsChanged(_ event: NSEvent) {
            guard let field, field.currentEditor() != nil else { return }
            let newFlags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            let pressed = newFlags.subtracting(heldModifierFlags)
            heldModifierFlags = newFlags
            for (flag, symbol) in Self.modifierSymbols where pressed.contains(flag) {
                insert(symbol, into: field)
            }
        }

        private func insert(_ symbol: String, into field: NSTextField) {
            guard let editor = field.currentEditor() else { return }
            let text = field.stringValue as NSString
            let range = editor.selectedRange
            let newText = text.replacingCharacters(in: range, with: symbol)
            field.stringValue = newText
            parent.text = newText
            let newCursor = range.location + (symbol as NSString).length
            editor.selectedRange = NSRange(location: newCursor, length: 0)
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            applyAutoReplaceIfNeeded(to: field)
            parent.text = field.stringValue
        }

        /// Mirrors AutoReplaceTextEditor's substitution, but after the fact:
        /// if the character immediately before the cursor is a non-uppercase
        /// boundary (almost always the space the user just typed) and the
        /// word right before that boundary is an exact ALL-CAPS match,
        /// swap it for its symbol and restore the cursor position. Still
        /// needed alongside the modifier-key capture above: it's the only
        /// way to get symbols (like TAB/RETURN/arrows) that have no physical
        /// "press it" equivalent here.
        private func applyAutoReplaceIfNeeded(to field: NSTextField) {
            guard let editor = field.currentEditor() else { return }
            let text = field.stringValue as NSString
            let cursor = editor.selectedRange.location
            guard cursor > 0, cursor <= text.length else { return }

            let boundaryChar = text.character(at: cursor - 1)
            guard let scalar = Unicode.Scalar(boundaryChar), !CharacterSet.uppercaseLetters.contains(scalar),
                  let match = TextReplacement.replacement(in: text, beforeLocation: cursor - 1)
            else { return }

            let boundaryString = text.substring(with: NSRange(location: cursor - 1, length: 1))
            let replacementText = match.replacement + boundaryString
            let fullRange = NSRange(location: match.range.location, length: cursor - match.range.location)

            field.stringValue = text.replacingCharacters(in: fullRange, with: replacementText)
            let newCursor = fullRange.location + (replacementText as NSString).length
            editor.selectedRange = NSRange(location: newCursor, length: 0)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertTab(_:)), let onTab = parent.onTab else { return false }
            onTab()
            return true
        }
    }
}
