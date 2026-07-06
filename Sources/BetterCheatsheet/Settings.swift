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
