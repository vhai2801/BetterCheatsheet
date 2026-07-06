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

    static func isRightSide(_ keyCode: UInt32) -> Bool {
        switch Int(keyCode) {
        case kVK_RightCommand, kVK_RightShift, kVK_RightOption, kVK_RightControl: return true
        default: return false
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
