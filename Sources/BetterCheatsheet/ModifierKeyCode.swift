import AppKit
import Carbon.HIToolbox

/// Maps physical left/right modifier virtual keyCodes to their semantic
/// NSEvent.ModifierFlags category, for recording/matching *which side* of a
/// modifier was pressed - something Carbon's RegisterEventHotKey can't do at
/// all (it only sees the generic left-or-right modifier bit).
enum ModifierKeyCode {
    static func category(for keyCode: UInt32) -> NSEvent.ModifierFlags? {
        switch Int(keyCode) {
        case kVK_Command, kVK_RightCommand: return .command
        case kVK_Shift, kVK_RightShift: return .shift
        case kVK_Option, kVK_RightOption: return .option
        case kVK_Control, kVK_RightControl: return .control
        default: return nil
        }
    }

    static func symbol(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_Command, kVK_RightCommand: return "⌘"
        case kVK_Shift, kVK_RightShift: return "⇧"
        case kVK_Option, kVK_RightOption: return "⌥"
        case kVK_Control, kVK_RightControl: return "⌃"
        default: return ""
        }
    }

    /// Fixed display order matching macOS convention: Control, Option, Shift, Command.
    static let categoryOrder: [(flag: NSEvent.ModifierFlags, left: UInt32, right: UInt32)] = [
        (.control, UInt32(kVK_Control), UInt32(kVK_RightControl)),
        (.option, UInt32(kVK_Option), UInt32(kVK_RightOption)),
        (.shift, UInt32(kVK_Shift), UInt32(kVK_RightShift)),
        (.command, UInt32(kVK_Command), UInt32(kVK_RightCommand)),
    ]

    /// Updates a set of currently-held physical modifier keyCodes given a
    /// `flagsChanged` event - shared by `HotKeyRecorderView` and
    /// `SideSensitiveHotKeyMonitor`, which both need to track which specific
    /// left/right modifier keys are down the same way: insert the keyCode
    /// when its category's flag is now set (a fresh press), or drop every
    /// keyCode in that same category when it's not (a release - there's
    /// only ever one side of a given modifier held at a time in practice,
    /// but this doesn't assume that).
    static func updating(_ held: Set<UInt32>, for event: NSEvent) -> Set<UInt32> {
        let keyCode = UInt32(event.keyCode)
        guard let category = category(for: keyCode) else { return held }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(category) {
            return held.union([keyCode])
        } else {
            return held.filter { self.category(for: $0) != category }
        }
    }

    /// Used when side-sensitivity is turned on but no side-specific recording
    /// has been made yet (e.g. migrating an older generic hotkey) - assumes
    /// the left-hand key for each modifier already in the generic mask, so
    /// the shortcut keeps working immediately instead of silently breaking.
    static func defaultLeftKeyCodes(forCarbonModifiers modifiers: UInt32) -> [UInt32] {
        var codes: [UInt32] = []
        if modifiers & UInt32(cmdKey) != 0 { codes.append(UInt32(kVK_Command)) }
        if modifiers & UInt32(shiftKey) != 0 { codes.append(UInt32(kVK_Shift)) }
        if modifiers & UInt32(optionKey) != 0 { codes.append(UInt32(kVK_Option)) }
        if modifiers & UInt32(controlKey) != 0 { codes.append(UInt32(kVK_Control)) }
        return codes
    }
}
