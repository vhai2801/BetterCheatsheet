import AppKit
import Carbon

/// Turns a (keyCode, Carbon modifiers) pair into a display string like "⌘⇧K".
enum HotKeyFormatter {
    /// The (keyEquivalent, modifierMask) pair for showing this hotkey as a
    /// native, right-aligned/dimmed NSMenuItem shortcut - purely cosmetic,
    /// since a status-item menu isn't part of NSApp.mainMenu so this
    /// keyEquivalent won't actually fire the global hotkey (HotKeyManager/
    /// SideSensitiveHotKeyMonitor do that separately). NSMenuItem has no
    /// left/right modifier concept, so a side-sensitive combo still displays
    /// using the generic `modifiers`/`keyCode` - e.g. a Right-Shift-only
    /// hotkey shows as plain ⇧. Returns nil if the key has no representable
    /// character at all (shouldn't happen for anything recordable via
    /// HotKeyRecorderView, but guards against an unmapped keyCode regardless).
    static func menuItemKeyEquivalent(for hotKey: HotKeyConfig) -> (key: String, mask: NSEvent.ModifierFlags)? {
        guard let key = menuItemKeyCharacter(for: hotKey.keyCode) else { return nil }
        var mask: NSEvent.ModifierFlags = []
        if hotKey.modifiers & UInt32(controlKey) != 0 { mask.insert(.control) }
        if hotKey.modifiers & UInt32(optionKey) != 0 { mask.insert(.option) }
        if hotKey.modifiers & UInt32(shiftKey) != 0 { mask.insert(.shift) }
        if hotKey.modifiers & UInt32(cmdKey) != 0 { mask.insert(.command) }
        return (key, mask)
    }

    /// Unlike `keyName(for:)` (a display symbol like "⏎" or "Space"), these
    /// are the literal characters/function-key constants NSMenuItem expects
    /// in its own `keyEquivalent` string for non-printable keys.
    private static let menuItemSpecialKeyCharacters: [UInt32: String] = [
        UInt32(kVK_Space): " ",
        UInt32(kVK_Return): "\r",
        UInt32(kVK_Tab): "\t",
        UInt32(kVK_Delete): "\u{8}",
        UInt32(kVK_ForwardDelete): "\u{F728}",
        UInt32(kVK_Escape): "\u{1B}",
        UInt32(kVK_LeftArrow): "\u{F702}",
        UInt32(kVK_RightArrow): "\u{F703}",
        UInt32(kVK_UpArrow): "\u{F700}",
        UInt32(kVK_DownArrow): "\u{F701}",
        UInt32(kVK_Home): "\u{F729}",
        UInt32(kVK_End): "\u{F72B}",
        UInt32(kVK_PageUp): "\u{F72C}",
        UInt32(kVK_PageDown): "\u{F72D}",
    ]

    private static func menuItemKeyCharacter(for keyCode: UInt32) -> String? {
        if let special = menuItemSpecialKeyCharacters[keyCode] { return special }
        return character(forKeyCode: keyCode)?.lowercased()
    }

    static func string(for hotKey: HotKeyConfig) -> String {
        if hotKey.sideSensitive && !hotKey.modifierKeyCodes.isEmpty {
            return sideSensitiveString(for: hotKey)
        }
        var result = ""
        if hotKey.modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if hotKey.modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if hotKey.modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if hotKey.modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        result += keyName(for: hotKey.keyCode)
        return result
    }

    /// e.g. "R⇧L⌘K" for a right-Shift + left-Command combo.
    private static func sideSensitiveString(for hotKey: HotKeyConfig) -> String {
        var result = ""
        let held = Set(hotKey.modifierKeyCodes)
        for category in ModifierKeyCode.categoryOrder {
            if held.contains(category.right) {
                result += "R" + ModifierKeyCode.symbol(for: category.right)
            } else if held.contains(category.left) {
                result += "L" + ModifierKeyCode.symbol(for: category.left)
            }
        }
        result += keyName(for: hotKey.keyCode)
        return result
    }

    static func keyName(for keyCode: UInt32) -> String {
        if let special = specialKeyNames[keyCode] {
            return special
        }
        if let character = character(forKeyCode: keyCode), !character.isEmpty {
            return character.uppercased()
        }
        return "Key\(keyCode)"
    }

    private static let specialKeyNames: [UInt32: String] = [
        UInt32(kVK_Space): "Space",
        UInt32(kVK_Return): "⏎",
        UInt32(kVK_Tab): "⇥",
        UInt32(kVK_Delete): "⌫",
        UInt32(kVK_ForwardDelete): "⌦",
        UInt32(kVK_Escape): "⎋",
        UInt32(kVK_LeftArrow): "←",
        UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑",
        UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_Home): "↖",
        UInt32(kVK_End): "↘",
        UInt32(kVK_PageUp): "⇞",
        UInt32(kVK_PageDown): "⇟",
    ]

    /// Resolves the base (unmodified) character for a virtual keyCode using the
    /// current keyboard layout, so letters/digits render correctly regardless
    /// of the user's input source.
    private static func character(forKeyCode keyCode: UInt32) -> String? {
        guard let inputSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else {
            return nil
        }
        guard let layoutDataRawPtr = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutDataRawPtr).takeUnretainedValue() as Data

        return layoutData.withUnsafeBytes { (rawBufferPointer: UnsafeRawBufferPointer) -> String? in
            guard let keyLayoutPtr = rawBufferPointer.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return nil
            }
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(
                keyLayoutPtr,
                UInt16(keyCode),
                UInt16(kUCKeyActionDown),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: length)
        }
    }
}
