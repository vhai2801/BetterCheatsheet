import AppKit
import SwiftUI

/// A rich-text NSTextView wrapper (bold, font family/size via the standard
/// Font Panel).
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
        context.coordinator.isProgrammaticUpdate = true
        textView.textStorage?.setAttributedString(attributedText)
        context.coordinator.isProgrammaticUpdate = false
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
            // setAttributedString(_:) triggers the same textDidChange path as
            // a user edit. Without this guard, every tab switch would
            // immediately write the just-set content straight back into the
            // model - a full RTF re-encode + tabs.json rewrite on the main
            // thread on every switch, which is exactly the kind of thing
            // that shows up as a perceptible hitch.
            context.coordinator.isProgrammaticUpdate = true
            textView.textStorage?.setAttributedString(attributedText)
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            context.coordinator.isProgrammaticUpdate = false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AutoReplaceTextEditor
        var isProgrammaticUpdate = false

        init(_ parent: AutoReplaceTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isProgrammaticUpdate, let textView = notification.object as? NSTextView else { return }
            parent.attributedText = textView.attributedString()
        }
    }
}
