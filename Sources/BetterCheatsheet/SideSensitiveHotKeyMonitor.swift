import AppKit

/// Alternative to HotKeyManager for when the user wants left/right modifier
/// side to matter. Carbon's RegisterEventHotKey has no concept of side at
/// all, so this tracks currently-held modifier keyCodes via a live
/// flagsChanged monitor and checks them against the recorded set on keyDown.
///
/// Global + local monitors together mirror how the Carbon hotkey behaves
/// everywhere, including while this app itself is frontmost: the global
/// monitor only sees events from other apps, the local one only sees events
/// while we're frontmost (and can swallow the match so it doesn't also type
/// into our own text fields).
final class SideSensitiveHotKeyMonitor {
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var currentlyHeld: Set<UInt32> = []

    func start(matching config: HotKeyConfig, onTrigger: @escaping () -> Void) {
        stop()

        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.updateHeldModifiers(with: event)
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.updateHeldModifiers(with: event)
            return event
        }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.matches(event: event, config: config) else { return }
            onTrigger()
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.matches(event: event, config: config) else { return event }
            onTrigger()
            return nil
        }
    }

    func stop() {
        for monitor in [globalFlagsMonitor, localFlagsMonitor, globalKeyMonitor, localKeyMonitor] {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
        globalFlagsMonitor = nil
        localFlagsMonitor = nil
        globalKeyMonitor = nil
        localKeyMonitor = nil
        currentlyHeld = []
    }

    private func updateHeldModifiers(with event: NSEvent) {
        let keyCode = UInt32(event.keyCode)
        guard let category = ModifierKeyCode.category(for: keyCode) else { return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(category) {
            currentlyHeld.insert(keyCode)
        } else {
            currentlyHeld = currentlyHeld.filter { ModifierKeyCode.category(for: $0) != category }
        }
    }

    private func matches(event: NSEvent, config: HotKeyConfig) -> Bool {
        UInt32(event.keyCode) == config.keyCode && currentlyHeld == Set(config.modifierKeyCodes)
    }

    deinit {
        stop()
    }
}
