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
}
