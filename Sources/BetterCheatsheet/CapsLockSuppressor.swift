import Darwin
import IOKit
import IOKit.hidsystem

/// Physically un-toggles Caps Lock the instant it engages, for a Caps Lock
/// key that's been remapped (e.g. to a Hyper key via Karabiner/Hammerspoon)
/// but whose remap doesn't fully suppress the OS's own native lock toggle -
/// the remap still delivers the intended modifier combo, but Caps Lock also
/// visibly (and functionally) engages alongside it. Uses the same
/// `IOHIDSetModifierLockState` trick long used by dedicated "disable Caps
/// Lock" utilities: a plain IOKit call against the HID system service, not
/// an Accessibility-gated event tap, so it needs no extra permission prompt
/// beyond what this app already requests for other features.
enum CapsLockSuppressor {
    private static let connection: io_connect_t = {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        var connect: io_connect_t = 0
        IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connect)
        IOObjectRelease(service)
        return connect
    }()

    /// Forces Caps Lock off if it's currently physically locked on. Safe to
    /// call unconditionally on every relevant key event - checks the actual
    /// hardware state first, so it's a no-op when Caps Lock is already off.
    static func forceOff() {
        var state = false
        guard IOHIDGetModifierLockState(connection, Int32(kIOHIDCapsLockState), &state) == KERN_SUCCESS,
              state
        else { return }
        IOHIDSetModifierLockState(connection, Int32(kIOHIDCapsLockState), false)
    }
}
