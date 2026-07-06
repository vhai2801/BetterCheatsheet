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

    private let fileURL: URL

    private struct Persisted: Codable {
        var theme: AppTheme
        var hotKey: HotKeyConfig
    }

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
        } else {
            theme = .light
            hotKey = HotKeyConfig(keyCode: DefaultHotKey.keyCode, modifiers: DefaultHotKey.modifiers)
        }
    }

    private func save() {
        let persisted = Persisted(theme: theme, hotKey: hotKey)
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
