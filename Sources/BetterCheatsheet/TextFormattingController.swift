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
