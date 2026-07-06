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

    var body: some View {
        ScrollView {
            if rows.isEmpty {
                Text(isEditable ? "No shortcuts yet - add one below" : "No shortcuts yet")
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("Shortcut")
                        Text("Action")
                        if isEditable {
                            Color.clear.frame(width: 16, height: 1)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Divider()
                        .gridCellColumns(isEditable ? 3 : 2)

                    ForEach($rows) { $row in
                        let isLastRow = row.id == rows.last?.id

                        GridRow {
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
                    }
                }
                .padding(12)
            }
        }
        .onAppear {
            applyPendingFocusIfNeeded(shouldFocus: focusFirstRowOnAppear)
        }
        .onChange(of: focusFirstRowOnAppear) { newValue in
            applyPendingFocusIfNeeded(shouldFocus: newValue)
        }
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
