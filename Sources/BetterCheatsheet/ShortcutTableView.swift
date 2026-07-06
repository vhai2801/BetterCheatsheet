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

    private let shortcutColumnMinWidth: CGFloat = 90
    private let actionColumnMinWidth: CGFloat = 120

    /// Row drag-to-reorder state - same gap-based design as TabBarView's tab
    /// reordering (track each row's frame, find which gap the drag's Y
    /// position falls in, commit on release), just tracking vertical
    /// position instead of horizontal. The existing row separator line
    /// doubles as the gap marker: normally a plain dim divider, it turns
    /// into an accent-colored drop indicator while a drag targets that gap.
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var gripFrames: [UUID: CGRect] = [:]
    @State private var draggingRowID: UUID?
    @State private var draggedRowOriginFrame: CGRect?
    @State private var draggedGripOriginFrame: CGRect?
    @State private var dragTranslation: CGFloat = 0
    @State private var insertionIndex: Int?

    private static let rowDragSpace = "BetterCheatsheet.rowDrag"

    var body: some View {
        ScrollView {
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
                        Text("Shortcut")
                        Text("Action")
                        if isEditable {
                            Color.clear.frame(width: 16, height: 1)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Divider()
                        .gridCellColumns(isEditable ? 4 : 2)

                    gapView(at: 0)

                    ForEach($rows) { $row in
                        let index = rows.firstIndex(where: { $0.id == row.id }) ?? 0
                        let isLastRow = index == rows.count - 1

                        GridRow {
                            if isEditable {
                                gripHandle(for: row.id)
                            }

                            cell(
                                for: $row.shortcut,
                                rowID: row.id,
                                minWidth: shortcutColumnMinWidth,
                                capturesModifierKeys: true
                            )

                            cell(
                                for: $row.action,
                                rowID: nil,
                                minWidth: actionColumnMinWidth,
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
            }
        }
        .coordinateSpace(name: Self.rowDragSpace)
        .onPreferenceChange(RowFramePreferenceKey.self) { rowFrames = $0 }
        .onPreferenceChange(GripFramePreferenceKey.self) { gripFrames = $0 }
        .overlay(alignment: .topLeading) {
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
    /// when `index == rows.count`). Interior gaps (strictly between two
    /// rows) always show the plain dim separator; the very top/bottom gaps
    /// are invisible except while actively targeted, since there was never
    /// a line before the first or after the last row. Any gap becomes a
    /// bold accent-colored drop indicator when it's the current drag target.
    private func gapView(at index: Int) -> some View {
        let isActive = draggingRowID != nil && insertionIndex == index
        let isInteriorGap = index > 0 && index < rows.count
        return Group {
            if isActive {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(height: 3)
            } else if isInteriorGap {
                Rectangle()
                    .fill(Color.primary.opacity(0.15))
                    .frame(height: 1)
            } else {
                Color.clear.frame(height: 1)
            }
        }
        .gridCellColumns(isEditable ? 4 : 2)
        .animation(.easeOut(duration: 0.12), value: insertionIndex)
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

    @ViewBuilder
    private func cell(
        for text: Binding<String>,
        rowID: UUID?,
        minWidth: CGFloat,
        onTab: (() -> Void)? = nil,
        capturesModifierKeys: Bool = false
    ) -> some View {
        if isEditable {
            ShortcutTableTextField(text: text, onTab: onTab, capturesModifierKeys: capturesModifierKeys)
                .frame(minWidth: minWidth, alignment: .leading)
                .modifier(FocusIfNeeded(focusedRowID: $focusedRowID, rowID: rowID))
        } else {
            Text(text.wrappedValue)
                .frame(minWidth: minWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
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
