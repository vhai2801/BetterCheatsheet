import AppKit
import SwiftUI

/// A rich-text NSTextView wrapper (bold, font family/size via the standard
/// Font Panel) that live-replaces exact ALL-CAPS keyword matches (see
/// TextReplacement.map) with their symbol as soon as a word boundary
/// character is typed after them.
struct AutoReplaceTextEditor: NSViewRepresentable {
    @Binding var attributedText: NSAttributedString
    var isEditable: Bool = true
    var formattingController: TextFormattingController?

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isEditable = isEditable
        textView.isRichText = true
        textView.usesFontPanel = true
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textStorage?.setAttributedString(attributedText)
        formattingController?.textView = textView

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        // Without this, the Coordinator keeps writing into whichever tab's
        // binding was current the moment it was first created, silently
        // routing every keystroke into the wrong tab's content.
        context.coordinator.parent = self

        guard let textView = nsView.documentView as? NSTextView else { return }
        textView.isEditable = isEditable
        formattingController?.textView = textView

        if textView.string != attributedText.string {
            textView.textStorage?.setAttributedString(attributedText)
            textView.setSelectedRange(NSRange(location: 0, length: 0))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AutoReplaceTextEditor

        init(_ parent: AutoReplaceTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.attributedText = textView.attributedString()
        }

        /// Intercepts a single incoming boundary character (anything that isn't an
        /// uppercase letter) and, if the word right before it is an exact ALL-CAPS
        /// match, substitutes the symbol instead of letting the boundary char land
        /// as-is after the untouched word.
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard let replacementString, replacementString.count == 1,
                  let scalar = replacementString.unicodeScalars.first,
                  !CharacterSet.uppercaseLetters.contains(scalar),
                  let textStorage = textView.textStorage else {
                return true
            }

            let currentText = textStorage.string as NSString
            guard let match = TextReplacement.replacement(in: currentText, beforeLocation: affectedCharRange.location) else {
                return true
            }

            let fullRange = NSRange(
                location: match.range.location,
                length: (affectedCharRange.location + affectedCharRange.length) - match.range.location
            )
            let combined = NSAttributedString(
                string: match.replacement + replacementString,
                attributes: textView.typingAttributes
            )

            textStorage.beginEditing()
            textStorage.replaceCharacters(in: fullRange, with: combined)
            textStorage.endEditing()

            textView.setSelectedRange(NSRange(location: fullRange.location + combined.length, length: 0))
            textView.didChangeText()
            return false
        }
    }
}
