import Foundation

enum TextReplacement {
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
