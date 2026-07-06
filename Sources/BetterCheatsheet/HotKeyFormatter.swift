import Carbon

/// Turns a (keyCode, Carbon modifiers) pair into a display string like "⌘⇧K".
enum HotKeyFormatter {
    static func string(for hotKey: HotKeyConfig) -> String {
        var result = ""
        if hotKey.modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if hotKey.modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if hotKey.modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if hotKey.modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
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
