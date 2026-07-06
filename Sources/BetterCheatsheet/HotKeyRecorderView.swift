import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Click to focus, then press a key combo to capture it as the new global
/// hotkey. Requires at least one modifier so it can't accidentally be bound
/// to a bare letter. Esc while recording cancels without changing anything.
/// Always captures which specific physical modifier keys (left/right) were
/// held, via flagsChanged, regardless of whether side-sensitivity is
/// currently turned on - so turning it on later doesn't require re-recording.
final class KeyRecorderNSView: NSView {
    var displayText: String = "" {
        didSet { needsDisplay = true }
    }
    /// keyCode, generic Carbon modifiers, specific held modifier keyCodes
    var onCapture: ((UInt32, UInt32, [UInt32]) -> Void)?

    private var isRecording = false {
        didSet { needsDisplay = true }
    }
    private var heldModifierKeyCodes: Set<UInt32> = []

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
        heldModifierKeyCodes = []
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else {
            super.flagsChanged(with: event)
            return
        }
        let keyCode = UInt32(event.keyCode)
        guard let category = ModifierKeyCode.category(for: keyCode) else { return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(category) {
            heldModifierKeyCodes.insert(keyCode)
        } else {
            heldModifierKeyCodes = heldModifierKeyCodes.filter { ModifierKeyCode.category(for: $0) != category }
        }
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
        onCapture?(UInt32(event.keyCode), carbonModifiers, Array(heldModifierKeyCodes))
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
    @Binding var hotKey: HotKeyConfig
    var displayText: String

    func makeNSView(context: Context) -> KeyRecorderNSView {
        let view = KeyRecorderNSView()
        view.displayText = displayText
        view.onCapture = { newKeyCode, newModifiers, newModifierKeyCodes in
            hotKey.keyCode = newKeyCode
            hotKey.modifiers = newModifiers
            hotKey.modifierKeyCodes = newModifierKeyCodes
        }
        return view
    }

    func updateNSView(_ nsView: KeyRecorderNSView, context: Context) {
        nsView.displayText = displayText
    }
}
