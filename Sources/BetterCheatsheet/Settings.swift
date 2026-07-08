import Foundation
import Combine

enum AppTheme: String, Codable, CaseIterable, Identifiable {
    case light, dark, frostedGlass

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .frostedGlass: return "Frosted Glass"
        }
    }
}

struct HotKeyConfig: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    /// Specific physical modifier keyCodes (left/right) captured while
    /// recording. Only enforced when `sideSensitive` is true; `modifiers`
    /// (the generic, side-agnostic mask) is what Carbon's RegisterEventHotKey
    /// actually uses otherwise.
    var modifierKeyCodes: [UInt32]
    var sideSensitive: Bool

    init(keyCode: UInt32, modifiers: UInt32, modifierKeyCodes: [UInt32] = [], sideSensitive: Bool = false) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.modifierKeyCodes = modifierKeyCodes
        self.sideSensitive = sideSensitive
    }

    private enum CodingKeys: String, CodingKey {
        case keyCode, modifiers, modifierKeyCodes, sideSensitive
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decode(UInt32.self, forKey: .keyCode)
        modifiers = try container.decode(UInt32.self, forKey: .modifiers)
        // Migrates configs saved before side-sensitivity existed.
        modifierKeyCodes = try container.decodeIfPresent([UInt32].self, forKey: .modifierKeyCodes) ?? []
        sideSensitive = try container.decodeIfPresent(Bool.self, forKey: .sideSensitive) ?? false
    }
}

/// Persists theme + global hotkey to disk (Application Support), independent
/// of the note tabs in AppState.
final class SettingsStore: ObservableObject {
    @Published var theme: AppTheme {
        didSet { save() }
    }
    @Published var hotKey: HotKeyConfig {
        didSet { save() }
    }
    /// Shared across every ShortcutTableView instance (main window and
    /// overlay both read the same SettingsStore) so a column resize sticks
    /// across tab switches and app relaunches, rather than resetting - a
    /// per-view @State would reset on every tab switch, since EditorView
    /// force-remounts ShortcutTableView per tab (see its `.id(tab.id)`).
    @Published var shortcutColumnWidth: CGFloat {
        didSet { save() }
    }
    @Published var shortcutColumnLeadingInset: CGFloat {
        didSet { save() }
    }
    /// Shared the same way as the column width/inset above - one value for
    /// both the main window and the overlay, surviving tab switches and
    /// relaunches.
    @Published var shortcutTableFontSize: CGFloat {
        didSet { save() }
    }
    /// Display-only: when true, read-only Shortcut cells (the overlay, and
    /// the drag-reorder floating badge) show `TextReplacement.spelledOut(_:)`
    /// ("Cmd Shift K") instead of the stored symbols ("⌘⇧K"). Doesn't touch
    /// what's actually stored, and doesn't affect the main window's editable
    /// Shortcut fields - those stay symbol-based, tied to the live physical-
    /// modifier-key capture feature.
    @Published var shortcutsDisplayAsText: Bool {
        didSet { save() }
    }
    /// Shared the same way as the column width/inset/font size above. A
    /// multiple (1, 1.25, 1.5, 2 - same options as the Note tab's line
    /// spacing menu, see EditorView.lineSpacingOptions) applied two ways at
    /// once in ShortcutTableView: scaling the Grid's row-to-row vertical
    /// spacing, and as `.lineSpacing(_:)` on the read-only (overlay) Shortcut/
    /// Action `Text` views specifically, for when long Action text wraps to
    /// more than one line there - the only place in this table any single
    /// cell ever spans multiple lines, since the main window's editable
    /// `NSTextField` cells are single-line only.
    @Published var shortcutTableLineSpacing: CGFloat {
        didSet { save() }
    }

    private let fileURL: URL

    private struct Persisted: Codable {
        var theme: AppTheme
        var hotKey: HotKeyConfig
        // Optional so decoding a settings.json saved before these fields
        // existed doesn't fail the whole decode (which would otherwise
        // silently reset theme/hotKey to defaults too).
        var shortcutColumnWidth: CGFloat?
        var shortcutColumnLeadingInset: CGFloat?
        var shortcutTableFontSize: CGFloat?
        var shortcutsDisplayAsText: Bool?
        var shortcutTableLineSpacing: CGFloat?
    }

    static let defaultShortcutColumnWidth: CGFloat = 90
    static let defaultShortcutTableFontSize: CGFloat = 16
    static let defaultShortcutTableLineSpacing: CGFloat = 1

    init() {
        let supportDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BetterCheatsheet", isDirectory: true)
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        fileURL = supportDir.appendingPathComponent("settings.json")

        // A single `decoded?.field ?? default` pass covers both "settings.json
        // exists and decoded fine" and "missing or corrupt" (decoded is nil,
        // so every field just takes its default) - no need for two full,
        // separately-maintained branches that only differed in one being
        // spelled `decoded.x ?? default` and the other just `default`.
        let decoded = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode(Persisted.self, from: $0) }
        theme = decoded?.theme ?? .light
        hotKey = decoded?.hotKey ?? HotKeyConfig(keyCode: DefaultHotKey.keyCode, modifiers: DefaultHotKey.modifiers)
        shortcutColumnWidth = decoded?.shortcutColumnWidth ?? Self.defaultShortcutColumnWidth
        shortcutColumnLeadingInset = decoded?.shortcutColumnLeadingInset ?? 0
        shortcutTableFontSize = decoded?.shortcutTableFontSize ?? Self.defaultShortcutTableFontSize
        shortcutsDisplayAsText = decoded?.shortcutsDisplayAsText ?? false
        shortcutTableLineSpacing = decoded?.shortcutTableLineSpacing ?? Self.defaultShortcutTableLineSpacing
    }

    private func save() {
        let persisted = Persisted(
            theme: theme,
            hotKey: hotKey,
            shortcutColumnWidth: shortcutColumnWidth,
            shortcutColumnLeadingInset: shortcutColumnLeadingInset,
            shortcutTableFontSize: shortcutTableFontSize,
            shortcutsDisplayAsText: shortcutsDisplayAsText,
            shortcutTableLineSpacing: shortcutTableLineSpacing
        )
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
