import Carbon.HIToolbox
import AppKit

/// Registers a single global hotkey via the Carbon Event Manager.
/// Deliberately not using a CGEventTap: RegisterEventHotKey works without
/// requesting Accessibility/Input Monitoring permission, which keeps first
/// launch friction-free for a small utility like this.
final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let onTrigger: () -> Void

    init(keyCode: UInt32, modifiers: UInt32, onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
        register(keyCode: keyCode, modifiers: modifiers)
    }

    private func register(keyCode: UInt32, modifiers: UInt32) {
        let hotKeyID = EventHotKeyID(signature: 0x4243_4853, id: 1) // "BCHS"
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue().onTrigger()
            return noErr
        }, 1, &eventType, selfPtr, &eventHandler)

        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}

enum DefaultHotKey {
    /// Cmd+Shift+K
    static let keyCode: UInt32 = UInt32(kVK_ANSI_K)
    static let modifiers: UInt32 = UInt32(cmdKey | shiftKey)
}
