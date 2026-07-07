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
    }

    static let defaultShortcutColumnWidth: CGFloat = 90
    static let defaultShortcutTableFontSize: CGFloat = 13

    init() {
        let supportDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BetterCheatsheet", isDirectory: true)
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        fileURL = supportDir.appendingPathComponent("settings.json")

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(Persisted.self, from: data) {
            theme = decoded.theme
            hotKey = decoded.hotKey
            shortcutColumnWidth = decoded.shortcutColumnWidth ?? Self.defaultShortcutColumnWidth
            shortcutColumnLeadingInset = decoded.shortcutColumnLeadingInset ?? 0
            shortcutTableFontSize = decoded.shortcutTableFontSize ?? Self.defaultShortcutTableFontSize
        } else {
            theme = .light
            hotKey = HotKeyConfig(keyCode: DefaultHotKey.keyCode, modifiers: DefaultHotKey.modifiers)
            shortcutColumnWidth = Self.defaultShortcutColumnWidth
            shortcutColumnLeadingInset = 0
            shortcutTableFontSize = Self.defaultShortcutTableFontSize
        }
    }

    private func save() {
        let persisted = Persisted(
            theme: theme,
            hotKey: hotKey,
            shortcutColumnWidth: shortcutColumnWidth,
            shortcutColumnLeadingInset: shortcutColumnLeadingInset,
            shortcutTableFontSize: shortcutTableFontSize
        )
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
