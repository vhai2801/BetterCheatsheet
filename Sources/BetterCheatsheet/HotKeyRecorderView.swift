import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Click to focus, then press a key combo to capture it as the new global
/// hotkey. Requires at least one modifier so it can't accidentally be bound
/// to a bare letter. Esc while recording cancels without changing anything.
final class KeyRecorderNSView: NSView {
    var displayText: String = "" {
        didSet { needsDisplay = true }
    }
    var onCapture: ((UInt32, UInt32) -> Void)?

    private var isRecording = false {
        didSet { needsDisplay = true }
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        if Int(event.keyCode) == kVK_Escape {
            isRecording = false
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbonModifiers: UInt32 = 0
        if flags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if flags.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }

        guard carbonModifiers != 0 else { return }

        isRecording = false
        onCapture?(UInt32(event.keyCode), carbonModifiers)
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    override func draw(_ dirtyRect: NSRect) {
        let background: NSColor = isRecording ? .selectedControlColor : .controlBackgroundColor
        let path = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
        background.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.stroke()

        let text = isRecording ? "Press new shortcut… (Esc to cancel)" : displayText
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.labelColor,
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
        ]
        let size = text.size(withAttributes: attributes)
        let origin = NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
        text.draw(at: origin, withAttributes: attributes)
    }
}

struct HotKeyRecorderView: NSViewRepresentable {
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32
    var displayText: String

    func makeNSView(context: Context) -> KeyRecorderNSView {
        let view = KeyRecorderNSView()
        view.displayText = displayText
        view.onCapture = { newKeyCode, newModifiers in
            keyCode = newKeyCode
            modifiers = newModifiers
        }
        return view
    }

    func updateNSView(_ nsView: KeyRecorderNSView, context: Context) {
        nsView.displayText = displayText
    }
}
