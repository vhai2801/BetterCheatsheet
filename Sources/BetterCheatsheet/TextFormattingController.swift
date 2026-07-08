import AppKit

/// Bridges SwiftUI toolbar buttons to whichever NSTextView is currently
/// mounted by AutoReplaceTextEditor. Applies to the current selection if
/// there is one, otherwise to typing attributes so the next characters typed
/// pick up the change.
final class TextFormattingController {
    weak var textView: NSTextView?

    func toggleBold() {
        modifyFont { font in
            let manager = NSFontManager.shared
            let isBold = manager.traits(of: font).contains(.boldFontMask)
            return isBold
                ? manager.convert(font, toNotHaveTrait: .boldFontMask)
                : manager.convert(font, toHaveTrait: .boldFontMask)
        }
    }

    func increaseFontSize() {
        modifyFont { NSFontManager.shared.convert($0, toSize: min($0.pointSize + 1, 48)) }
    }

    func decreaseFontSize() {
        modifyFont { NSFontManager.shared.convert($0, toSize: max($0.pointSize - 1, 8)) }
    }

    func showFontPanel() {
        guard let textView, let window = textView.window else { return }
        window.makeFirstResponder(textView)
        NSFontManager.shared.target = textView
        NSFontManager.shared.orderFrontFontPanel(nil)
    }

    /// Sets line spacing, expressed as the same "1/1.25/1.5/2" multiples
    /// the toolbar menu shows (see EditorView.lineSpacingOptions), by
    /// adding `NSParagraphStyle.lineSpacing` - extra points inserted
    /// *between* line fragments - rather than `lineHeightMultiple`, which
    /// was tried first and reverted: that property scales each line's own
    /// full box (ascender through descender), and since AppKit derives the
    /// blinking insertion-point cursor's size from that same box, the
    /// cursor visibly ballooned right along with the spacing at anything
    /// above 1x. `lineSpacing` doesn't fully avoid this either - confirmed
    /// the cursor still renders oversized on every line *after* a break
    /// (AppKit bakes the leading gap into that next line's own box too),
    /// though at least the first/only line of a paragraph stays normal.
    /// Two attempts at manually redrawing the cursor to compensate
    /// (`drawInsertionPoint` overrides in a custom NSTextView subclass, one
    /// guessing a fixed offset, one computing the real baseline from the
    /// layout manager) were both tried and reverted - accepted as a known
    /// cosmetic limitation per direct request rather than pursued further.
    /// Unlike `modifyFont`, which only ever
    /// touches the selection or (with no selection) `typingAttributes`,
    /// this also applies across the *entire* note when there's no
    /// selection - line spacing reads as a whole-note setting ("make this
    /// note more readable"), not a per-character one, and a Note tab is
    /// short freeform text rather than a long multi-page document where
    /// "just the current paragraph" would matter more.
    func setLineSpacing(_ multiple: CGFloat) {
        guard let textView, let textStorage = textView.textStorage else { return }
        let selectedRange = textView.selectedRange()
        let applyRange = selectedRange.length > 0 ? selectedRange : NSRange(location: 0, length: textStorage.length)

        // One representative font size for the whole edit (whatever the
        // cursor/selection's own font already is), not a per-character
        // lookup - line spacing reads as one whole-paragraph setting, the
        // same way Word/Docs treat it, not something that needs to track
        // mixed font sizes exactly.
        let referenceSize = ((textView.typingAttributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 13)).pointSize
        let extraGap = (multiple - 1) * referenceSize

        if applyRange.length > 0 {
            textStorage.beginEditing()
            textStorage.enumerateAttribute(.paragraphStyle, in: applyRange, options: []) { value, subrange, _ in
                textStorage.addAttribute(.paragraphStyle, value: Self.paragraphStyle(from: value as? NSParagraphStyle, lineSpacing: extraGap), range: subrange)
            }
            textStorage.endEditing()
            textView.didChangeText()
        }

        // Always also updated so an empty note (nothing for the range-based
        // pass above to touch) and anything typed after this still gets the
        // chosen spacing.
        textView.typingAttributes[.paragraphStyle] = Self.paragraphStyle(from: textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle, lineSpacing: extraGap)
    }

    private static func paragraphStyle(from existing: NSParagraphStyle?, lineSpacing: CGFloat) -> NSParagraphStyle {
        let style = (existing?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        // Explicitly zeroed, not left alone - an earlier version of this
        // feature set `lineHeightMultiple` instead of `lineSpacing` (see
        // this method's caller's doc comment), so any note edited during
        // that testing still has it baked into its saved content. Since
        // this method never used to touch that property, it stayed set
        // and stacked with the new `lineSpacing` value every time - "1"
        // looked like it did nothing (the stale multiple was still
        // inflating every line) and "2" looked huge (both applied at
        // once). Clearing it here whenever spacing is set migrates any
        // such note off the old attribute for good.
        style.lineHeightMultiple = 0
        return style
    }

    private func modifyFont(_ transform: (NSFont) -> NSFont) {
        guard let textView, let textStorage = textView.textStorage else { return }
        let range = textView.selectedRange()

        if range.length > 0 {
            textStorage.beginEditing()
            textStorage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
                let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: 13)
                textStorage.addAttribute(.font, value: transform(font), range: subrange)
            }
            textStorage.endEditing()
            textView.didChangeText()
        } else {
            let font = (textView.typingAttributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 13)
            textView.typingAttributes[.font] = transform(font)
        }
    }
}
