import ApplicationServices

/// Side-sensitive hotkey matching needs a real-time global key event monitor
/// (unlike Carbon's RegisterEventHotKey), which macOS only delivers to
/// trusted/Accessibility-permitted apps.
enum AccessibilityPermission {
    @discardableResult
    static func requestIfNeeded() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }
}
