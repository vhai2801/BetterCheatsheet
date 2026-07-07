import Foundation

enum TextReplacement {
    /// Exact, whole, ALL-CAPS keyword -> symbol, used only by the Trackpad
    /// template's Shortcut column (see ShortcutTableView's
    /// `applyAutoReplaceIfNeeded`) - the Keyboard template instead captures
    /// physical modifier/key presses directly, which doesn't make sense for
    /// a trackpad gesture description typed as free text. This is the same
    /// table that used to back live-typing auto-replace for the Keyboard
    /// template too, before physical-key capture superseded it there (see
    /// Decisions log, 2026-07-07). Extend freely.
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
    private static let symbolNames: [Character: String] = [
        "⌘": "Cmd", "⌥": "Option", "⌃": "Ctrl", "⇧": "Shift",
        "⇪": "Caps Lock", "⇥": "Tab", "⏎": "Return", "⌫": "Delete",
        "⌦": "Fwd Delete", "⎋": "Esc", "␣": "Space",
        "↑": "Up", "↓": "Down", "←": "Left", "→": "Right",
        "⇞": "Page Up", "⇟": "Page Down", "↖": "Home", "↘": "End",
    ]

    /// The exceptions to "every symbol is a single character": Hyper
    /// (Ctrl+Opt+Cmd+Shift at once, see ShortcutTableView's `hyperFlags`)
    /// and Fn (no single glyph the way ⌘⇧⌥⌃ have one) are both captured as
    /// a literal word followed by a space, not a single glyph - already
    /// spelled out, so each is matched and passed through as its own token
    /// rather than exploded letter-by-letter below. Longest-first so a
    /// shorter token can't shadow a longer one sharing the same prefix
    /// (not the case for these two specifically, but cheap to keep true).
    private static let literalTokens = ["Hyper", "fn"].sorted { $0.count > $1.count }

    /// Converts a shortcut string built from the symbols above (e.g.
    /// "⌘⇧K") into a spelled-out equivalent ("Cmd Shift K"). Characters
    /// with no known name - the actual key itself, e.g. "K" - pass through
    /// unchanged. Shortcuts are otherwise always a run of single-character
    /// symbols followed by one single-character key (physical modifier/key
    /// capture only ever inserts single characters, `literalTokens` aside),
    /// so splitting and rejoining by character is safe for well-formed
    /// shortcuts; arbitrary free text typed into the field instead would
    /// just come out oddly spaced, not garbled.
    static func spelledOut(_ shortcut: String) -> String {
        guard !shortcut.isEmpty else { return shortcut }

        var tokens: [String] = []
        var remainder = Substring(shortcut)
        while !remainder.isEmpty {
            if let match = literalTokens.first(where: { remainder.hasPrefix($0) }) {
                tokens.append(match)
                remainder.removeFirst(match.count)
                // Both literal tokens are always inserted with a trailing
                // space (see ShortcutTableView) - drop it here rather than
                // let it fall through to the loop below, where it'd become
                // its own (empty, since space isn't in symbolNames) token
                // and add a second, redundant separator next to the one
                // `joined` already adds between tokens.
                if remainder.first == " " {
                    remainder.removeFirst()
                }
            } else {
                let ch = remainder.removeFirst()
                tokens.append(symbolNames[ch] ?? String(ch))
            }
        }
        return tokens.joined(separator: " ")
    }
}
