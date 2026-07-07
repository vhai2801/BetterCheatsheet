import Foundation

enum TextReplacement {
    /// Exact, whole, ALL-CAPS keyword -> symbol. Extend freely.
    static let map: [String: String] = [
        "CMD": "⌘", "COMMAND": "⌘",
        "OPTION": "⌥", "ALT": "⌥",
        "CTRL": "⌃", "CONTROL": "⌃",
        "SHIFT": "⇧",
        "CAPSLOCK": "⇪",
        "TAB": "⇥",
        "RETURN": "⏎", "ENTER": "⏎",
        "DELETE": "⌫", "BACKSPACE": "⌫",
        "ESC": "⎋", "ESCAPE": "⎋",
        "SPACE": "␣",
        "UP": "↑", "DOWN": "↓", "LEFT": "←", "RIGHT": "→",
        "PAGEUP": "⇞", "PAGEDOWN": "⇟",
        "HOME": "↖", "END": "↘",
    ]

    /// Looks at the word immediately before `beforeLocation` (an index into `text`, typically
    /// where a just-typed boundary character - space, punctuation, newline - is about to land).
    /// If that word is an exact ALL-CAPS match in `map`, returns its range and the replacement
    /// symbol. Returns nil otherwise (including when the preceding text isn't all-uppercase-letters,
    /// so mixed-case or lowercase words like "Cmd"/"cmd" are correctly left untouched).
    static func replacement(in text: NSString, beforeLocation: Int) -> (range: NSRange, replacement: String)? {
        guard beforeLocation > 0, beforeLocation <= text.length else { return nil }

        var start = beforeLocation
        while start > 0 {
            let ch = text.character(at: start - 1)
            guard let scalar = Unicode.Scalar(ch), CharacterSet.uppercaseLetters.contains(scalar) else { break }
            start -= 1
        }
        guard start < beforeLocation else { return nil }

        let range = NSRange(location: start, length: beforeLocation - start)
        let word = text.substring(with: range)
        guard let symbol = map[word] else { return nil }
        return (range, symbol)
    }

    /// Symbol -> spelled-out name, for the Settings toggle that displays
    /// shortcuts as text instead of symbols (e.g. "⌘⇧K" -> "Cmd Shift K").
    /// Deliberately a separate table from `map` above rather than reusing
    /// it in reverse: `map` is keyed by ALL-CAPS keywords for live-typing
    /// auto-replace, with duplicate entries ("CMD"/"COMMAND" -> "⌘") that
    /// don't have a single obvious reverse, and different capitalization
    /// needs ("Cmd", not "CMD" or "COMMAND", reads better in a display).
    private static let symbolNames: [Character: String] = [
        "⌘": "Cmd", "⌥": "Option", "⌃": "Ctrl", "⇧": "Shift",
        "⇪": "Caps Lock", "⇥": "Tab", "⏎": "Return", "⌫": "Delete",
        "⌦": "Fwd Delete", "⎋": "Esc", "␣": "Space",
        "↑": "Up", "↓": "Down", "←": "Left", "→": "Right",
        "⇞": "Page Up", "⇟": "Page Down", "↖": "Home", "↘": "End",
    ]

    /// Converts a shortcut string built from the symbols above (e.g.
    /// "⌘⇧K") into a spelled-out equivalent ("Cmd Shift K"). Characters
    /// with no known name - the actual key itself, e.g. "K" - pass through
    /// unchanged. Shortcuts are always a run of single-character symbols
    /// followed by one single-character key (however it was entered -
    /// physical modifier capture or the ALL-CAPS auto-replace both only
    /// ever insert single characters), so splitting and rejoining by
    /// character is safe for well-formed shortcuts; arbitrary free text
    /// typed into the field instead would just come out oddly spaced,
    /// not garbled.
    static func spelledOut(_ shortcut: String) -> String {
        guard !shortcut.isEmpty else { return shortcut }
        return shortcut.map { symbolNames[$0] ?? String($0) }.joined(separator: " ")
    }
}
